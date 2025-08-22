# /opt/HX-Infrastructure-/api-gateway/gateway/src/middlewares/validation.py
from typing import Any

from fastapi import Response

from .base import MiddlewareBase


class ValidationMiddleware(MiddlewareBase):
    # Define read-only endpoints that allow GET and HEAD
    READ_ONLY_ENDPOINTS = {"/v1/models"}

    async def process(self, context: dict[str, Any]) -> dict[str, Any]:
        req = context.get("request")
        if req is None:
            # Safe exit if request is missing
            return context

        if req.url.path.startswith("/v1/"):
            # Check if this is a read-only endpoint
            if req.url.path in self.READ_ONLY_ENDPOINTS:
                # Allow GET and HEAD for read-only endpoints
                if req.method not in ("GET", "HEAD", "POST"):
                    context["response"] = Response(
                        status_code=405,
                        content=b"Method Not Allowed",
                        headers={"Allow": "GET, HEAD, POST"},
                    )
                    return context
            else:
                # For other endpoints, only allow POST
                if req.method != "POST":
                    context["response"] = Response(
                        status_code=405,
                        content=b"Method Not Allowed",
                        headers={"Allow": "POST"},
                    )
                    return context
        return context
