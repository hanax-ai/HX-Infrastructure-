# /opt/HX-Infrastructure-/api-gateway/gateway/src/middlewares/security.py
import os
import logging
from fastapi import Response
from typing import Any, Dict
from .base import MiddlewareBase

# Development-only default key - NOT for production use
DEV_DEFAULT_MASTER_KEY = "sk-hx-dev-1234"

class SecurityMiddleware(MiddlewareBase):
    def __init__(self):
        super().__init__()
        # Initialize master key checking both environment variables
        self.master_key = os.getenv("HX_MASTER_KEY") or os.getenv("MASTER_KEY") or DEV_DEFAULT_MASTER_KEY
        if self.master_key == DEV_DEFAULT_MASTER_KEY:
            logging.warning(
                "Using development default master key. "
                "Set HX_MASTER_KEY or MASTER_KEY environment variable for production use."
            )
    
    async def process(self, context: Dict[str, Any]) -> Dict[str, Any]:
        request = context["request"]
        # Allow liveness without auth
        if request.url.path in ("/healthz", "/livez", "/readyz"):
            return context
        auth = request.headers.get("authorization", "")
        if not auth.lower().startswith("bearer ") or auth.split(" ", 1)[1] != self.master_key:
            context["response"] = Response(
                status_code=401, 
                content=b"Unauthorized",
                headers={"WWW-Authenticate": "Bearer"}
            )
            return context
        return context
