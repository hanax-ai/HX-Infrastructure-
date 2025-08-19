# /opt/HX-Infrastructure-/api-gateway/gateway/src/middlewares/routing.py
import os, json, yaml
import logging
from typing import Any, Dict, List
from fastapi import Response
from .base import MiddlewareBase
from ..routing.selector import ModelSelectionAlgorithm

CFG_DIR = "/opt/HX-Infrastructure-/api-gateway/config/api-gateway"

class RoutingMiddleware(MiddlewareBase):
    def __init__(self) -> None:
        self._registry = None
        self._routing = None
        self._algo = ModelSelectionAlgorithm()
        self.logger = logging.getLogger(__name__)

    def _load_configs(self):
        if self._registry is None:
            try:
                with open(f"{CFG_DIR}/model_registry.yaml", "r") as f:
                    self._registry = yaml.safe_load(f) or {}
            except (FileNotFoundError, OSError, yaml.YAMLError) as e:
                self.logger.error(f"Failed to load model registry: {e}")
                self._registry = {}
        
        if self._routing is None:
            try:
                with open(f"{CFG_DIR}/routing.yaml", "r") as f:
                    self._routing = yaml.safe_load(f) or {}
            except (FileNotFoundError, OSError, yaml.YAMLError) as e:
                self.logger.error(f"Failed to load routing config: {e}")
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
        body_bytes = await req.body()
        try:
            payload = json.loads(body_bytes or "{}")
        except Exception:
            context["response"] = Response(status_code=400, content=b"Bad JSON")
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
        candidates = [m for m in all_models if m.get("group") == group]

        selected = self._algo.select(candidates, req_ctx) if candidates else None

        if not selected:
            # Fallback to static weights / failover order with safe access
            failover_order = routing_config.get("failover_order", [])
            payload["model"] = failover_order[0] if isinstance(failover_order, list) and failover_order else None
        else:
            payload["model"] = selected["name"]

        context["normalized_body"] = json.dumps(payload).encode("utf-8")
        return context
