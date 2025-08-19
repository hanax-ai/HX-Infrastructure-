# /opt/HX-Infrastructure-/api-gateway/gateway/src/middlewares/transform.py
import json
from typing import Any, Dict
from fastapi import Response
from .base import MiddlewareBase

class TransformMiddleware(MiddlewareBase):
    async def process(self, context: Dict[str, Any]) -> Dict[str, Any]:
        req = context["request"]
        if req.url.path == "/v1/embeddings":
            try:
                body_bytes = await req.body()
            except Exception as e:
                context["response"] = Response(
                    status_code=400, 
                    content=f"Failed to read request body: {str(e)}".encode("utf-8")
                )
                return context
            
            try:
                payload = json.loads(body_bytes or "{}")
            except Exception:
                context["response"] = Response(status_code=400, content=b"Bad JSON")
                return context
            # Defensive normalization: if "input" present, normalize to "input" (OpenAI)
            # and add an internal alias "prompt" for downstream providers if needed.
            if "input" in payload and "prompt" not in payload:
                payload["prompt"] = payload["input"]
            # Re-inject normalized body
            context["normalized_body"] = json.dumps(payload).encode("utf-8")
        return context
