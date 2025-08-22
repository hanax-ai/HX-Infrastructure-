# /opt/HX-Infrastructure-/api-gateway/gateway/src/middlewares/transform.py
import json
import logging
from typing import Any

from starlette.responses import JSONResponse

from .base import MiddlewareBase


class TransformMiddleware(MiddlewareBase):
    def __init__(self):
        super().__init__()
        self.logger = logging.getLogger(__name__)

    async def process(self, context: dict[str, Any]) -> dict[str, Any]:
        request = context["request"]

        # Only apply this transformation to the /v1/embeddings endpoint
        if request.url.path != "/v1/embeddings" or request.method != "POST":
            return context

        try:
            body_bytes = await request.body()
            if not body_bytes:
                return context  # Pass through if no body

            # Cache the body so it can be read again by downstream middleware
            context["request_body_bytes"] = body_bytes

            # Create a new `receive` callable that returns the cached body
            async def receive():
                return {"type": "http.request", "body": body_bytes, "more_body": False}

            # Replace the original `receive` callable
            request._receive = receive

        except Exception as e:
            self.logger.error(f"Failed to read request body for /v1/embeddings: {e}")
            context["response"] = JSONResponse(
                status_code=400, content={"error": "Failed to read request body"}
            )
            return context

        try:
            payload = json.loads(body_bytes)
        except json.JSONDecodeError as e:
            self.logger.error(f"Invalid JSON in request for /v1/embeddings: {e}")
            context["response"] = JSONResponse(
                status_code=400, content={"error": "Invalid JSON in request body"}
            )
            return context

        # Idempotent transformation: map 'prompt' to 'input' only if 'input' is missing.
        if "prompt" in payload and "input" not in payload:
            self.logger.debug("Transforming 'prompt' to 'input' for /v1/embeddings")
            payload["input"] = payload.pop("prompt")
            # Store the modified body back in the context for the ExecutionMiddleware.
            context["transformed_body"] = json.dumps(payload).encode("utf-8")

        return context
