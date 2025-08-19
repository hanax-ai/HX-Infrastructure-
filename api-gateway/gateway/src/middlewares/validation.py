# /opt/HX-Infrastructure-/api-gateway/gateway/src/middlewares/validation.py
from typing import Any, Dict
from fastapi import Response
from .base import MiddlewareBase

class ValidationMiddleware(MiddlewareBase):
    async def process(self, context: Dict[str, Any]) -> Dict[str, Any]:
        req = context["request"]
        if req.method != "POST" and req.url.path.startswith("/v1/"):
            context["response"] = Response(status_code=405, content=b"Method Not Allowed")
            return context
        return context
