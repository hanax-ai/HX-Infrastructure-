# /opt/HX-Infrastructure-/api-gateway/gateway/src/gateway_pipeline.py
from typing import Any, Dict, List, Optional
from fastapi import Request, Response
from .middlewares.base import MiddlewareBase
from .middlewares.security import SecurityMiddleware
from .middlewares.validation import ValidationMiddleware
from .middlewares.transform import TransformMiddleware
from .middlewares.routing import RoutingMiddleware
from .middlewares.execution import ExecutionMiddleware

class GatewayPipeline:
    def __init__(self, middlewares: Optional[List[MiddlewareBase]] = None):
        self.stages = middlewares or [
            SecurityMiddleware(),
            ValidationMiddleware(),
            TransformMiddleware(),
            RoutingMiddleware(),
            ExecutionMiddleware(),
        ]

    async def process_request(self, request: Request) -> Response:
        context: Dict[str, Any] = {"request": request, "response": None}
        for stage in self.stages:
            context = await stage.process(context)
            # Early return if a stage created a response (e.g., auth fail)
            if context.get("response") is not None:
                return context["response"]
        # ExecutionMiddleware should set response
        return context.get("response", Response(status_code=502, content=b"Bad Gateway"))
