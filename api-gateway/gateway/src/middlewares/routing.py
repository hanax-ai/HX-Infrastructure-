# /opt/HX-Infrastructure-/api-gateway/gateway/src/middlewares/routing.py
import os
import json
import yaml
import logging
from typing import Any, Dict, List
from fastapi import Response
from .base import MiddlewareBase
from ..routing.selector import ModelSelectionAlgorithm

CFG_DIR = os.environ.get("API_GATEWAY_CFG_DIR", "/opt/HX-Infrastructure-/api-gateway/config/api-gateway")

class RoutingMiddleware(MiddlewareBase):
    def __init__(self) -> None:
        self._registry = None
        self._routing = None
        self._algo = ModelSelectionAlgorithm()
        self.logger = logging.getLogger(__name__)
        # Cache environment variables to avoid repeated lookups
        self._max_body_size = int(os.environ.get("HX_MAX_ROUTING_BODY_SIZE", "65536"))

    def _load_configs(self):
        """Load configuration files with comprehensive error handling and validation"""
        if self._registry is None:
            try:
                registry_path = f"{CFG_DIR}/model_registry.yaml"
                with open(registry_path, "r") as f:
                    content = f.read()
                    if not content.strip():
                        self.logger.warning(f"Model registry file {registry_path} is empty")
                        self._registry = {}
                    else:
                        self._registry = yaml.safe_load(content)
                        if not isinstance(self._registry, dict):
                            self.logger.error(f"Model registry must be a dictionary, got {type(self._registry)}")
                            self._registry = {}
                        
                        # Validate registry structure
                        if "models" in self._registry and not isinstance(self._registry["models"], list):
                            self.logger.error("Model registry 'models' field must be a list")
                            self._registry = {}
                            
            except FileNotFoundError:
                self.logger.warning(f"Model registry file not found: {CFG_DIR}/model_registry.yaml")
                self._registry = {}
            except PermissionError as e:
                self.logger.error(f"Permission denied reading model registry: {e}")
                self._registry = {}
            except yaml.YAMLError as e:
                self.logger.error(f"YAML parse error in model registry: {e}")
                self._registry = {}
            except Exception as e:
                self.logger.error(f"Unexpected error loading model registry: {e}")
                self._registry = {}
        
        if self._routing is None:
            try:
                routing_path = f"{CFG_DIR}/routing.yaml"
                with open(routing_path, "r") as f:
                    content = f.read()
                    if not content.strip():
                        self.logger.warning(f"Routing config file {routing_path} is empty")
                        self._routing = {}
                    else:
                        self._routing = yaml.safe_load(content)
                        if not isinstance(self._routing, dict):
                            self.logger.error(f"Routing config must be a dictionary, got {type(self._routing)}")
                            self._routing = {}
                            
            except FileNotFoundError:
                self.logger.warning(f"Routing config file not found: {CFG_DIR}/routing.yaml")
                self._routing = {}
            except PermissionError as e:
                self.logger.error(f"Permission denied reading routing config: {e}")
                self._routing = {}
            except yaml.YAMLError as e:
                self.logger.error(f"YAML parse error in routing config: {e}")
                self._routing = {}
            except Exception as e:
                self.logger.error(f"Unexpected error loading routing config: {e}")
                self._routing = {}

    async def process(self, context: Dict[str, Any]) -> Dict[str, Any]:
        self._load_configs()
        req = context["request"]
        if not req.url.path.startswith("/v1/chat/completions"):
            return context

        # Build req_ctx (future: estimate tokens/complexity)
        req_ctx = {
            "estimated_tokens": 512,
            "complexity_score": 1.0,
            "domain": req.headers.get("x-hx-domain"),
        }

        # Parse body so we can set model if group provided (or default group)
        try:
            body_bytes = await req.body()
            # Validate body size to prevent memory exhaustion
            max_body_size = self._max_body_size  # 64KB default
            if len(body_bytes) > max_body_size:
                self.logger.error(f"Request body too large: {len(body_bytes)} bytes (max: {max_body_size})")
                context["response"] = Response(
                    status_code=413, 
                    content=b'{"error": "Payload too large for routing processing"}',
                    media_type="application/json"
                )
                return context
                
            payload = json.loads(body_bytes or "{}")
            if not isinstance(payload, dict):
                self.logger.error(f"Invalid payload type: expected dict, got {type(payload)}")
                context["response"] = Response(
                    status_code=400, 
                    content=b'{"error": "Request body must be a JSON object"}',
                    media_type="application/json"
                )
                return context
                
        except json.JSONDecodeError as e:
            self.logger.error(f"JSON decode error: {e}")
            context["response"] = Response(
                status_code=400, 
                content=b'{"error": "Invalid JSON in request body"}',
                media_type="application/json"
            )
            return context
        except Exception as e:
            self.logger.error(f"Unexpected error parsing request body: {e}")
            context["response"] = Response(
                status_code=500, 
                content=b'{"error": "Internal server error processing request"}',
                media_type="application/json"
            )
            return context

        # If caller already set an explicit model, respect it
        if "model" in payload and isinstance(payload["model"], str):
            context["normalized_body"] = json.dumps(payload).encode("utf-8")
            return context

        # Safe configuration access with defaults
        routing_config = self._routing.get("routing", {}) if isinstance(self._routing, dict) else {}
        default_group = routing_config.get("default_group", "default")
        group = req.headers.get("x-hx-model-group") or default_group
        
        all_models: List[Dict[str, Any]] = self._registry.get("models", []) if isinstance(self._registry, dict) else []
        candidates = [m for m in all_models if isinstance(m, dict) and m.get("group") == group]

        selected = self._algo.select(candidates, req_ctx) if candidates else None

        if not selected:
            # Fallback to static weights / failover order with safe access
            failover_order = routing_config.get("failover_order", [])
            payload["model"] = failover_order[0] if isinstance(failover_order, list) and failover_order else None
        else:
            # Safe access to selected model name or id, avoid null values
            if isinstance(selected, dict):
                model_identifier = selected.get("name") or selected.get("id")
                if model_identifier:
                    payload["model"] = model_identifier
                # If neither name nor id exists, don't set the model key to avoid JSON null

        context["normalized_body"] = json.dumps(payload).encode("utf-8")
        return context
