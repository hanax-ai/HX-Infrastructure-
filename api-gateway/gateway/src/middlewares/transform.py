# /opt/HX-Infrastructure-/api-gateway/gateway/src/middlewares/transform.py
import json
import logging
from typing import Any, Dict
from fastapi import Response
from .base import MiddlewareBase

class TransformMiddleware(MiddlewareBase):
    def __init__(self):
        super().__init__()
        self.logger = logging.getLogger(__name__)

    async def process(self, context: Dict[str, Any]) -> Dict[str, Any]:
        req = context["request"]
        if req.url.path == "/v1/embeddings":
            try:
                body_bytes = await req.body()
            except Exception as e:
                # Log server-side but don't leak details to client
                self.logger.error(f"Failed to read request body: {e}")
                context["response"] = Response(
                    status_code=400,
                    content=json.dumps({"error": "Failed to read request body"}).encode("utf-8"),
                    media_type="application/json"
                )
                return context
            
            try:
                payload = json.loads(body_bytes or "{}")
            except Exception as e:
                # Log server-side but don't leak details to client
                self.logger.error(f"Failed to parse JSON: {e}")
                context["response"] = Response(
                    status_code=400,
                    content=json.dumps({"error": "Invalid JSON"}).encode("utf-8"),
                    media_type="application/json"
                )
                return context
            # Defensive normalization: if "input" present, normalize to "input" (OpenAI)
            # and add an internal alias "prompt" for downstream providers if needed.
            if "input" in payload and "prompt" not in payload:
                payload["prompt"] = payload["input"]
            # Re-inject normalized body
            context["normalized_body"] = json.dumps(payload).encode("utf-8")
        return context
