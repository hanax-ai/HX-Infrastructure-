# /opt/HX-Infrastructure-/api-gateway/gateway/src/gateway_pipeline.py
import os
from typing import Any, Dict, List, Optional
from fastapi import Request, Response
from .middlewares.base import MiddlewareBase
from .middlewares.security import SecurityMiddleware
from .middlewares.validation import ValidationMiddleware
from .middlewares.transform import TransformMiddleware
from .middlewares.routing import RoutingMiddleware
from .middlewares.execution import ExecutionMiddleware
from .middlewares.db_guard import DBGuardMiddleware
from .services.postgres_service import PostgresService
from .services.redis_service import RedisService
from .services.qdrant_service import QdrantService

class GatewayPipeline:
    def __init__(self, middlewares: Optional[List[MiddlewareBase]] = None):
        if middlewares is None:
            # Initialize database services
            db_config = {
                'postgres_url': os.getenv("PG_URL"),
                'redis_url': os.getenv("REDIS_URL"), 
                'qdrant_url': os.getenv("QDRANT_URL")
            }
            
            # Create DB-Guard middleware with service configuration
            dbguard = DBGuardMiddleware(db_config)
            
            # Pipeline: Security -> DB-Guard -> Validation -> Transform -> Routing -> Execution  
            middlewares = [
                SecurityMiddleware(),
                dbguard,
                ValidationMiddleware(),
                TransformMiddleware(),
                RoutingMiddleware(),
                ExecutionMiddleware(),
            ]
        
        self.stages = middlewares

    async def process_request(self, request: Request) -> Response:
        context: Dict[str, Any] = {"request": request, "response": None}
        for stage in self.stages:
            context = await stage.process(context)
            # Early return if a stage created a response (e.g., auth fail)
            if context.get("response") is not None:
                return context["response"]
        # ExecutionMiddleware should set response
        return context.get("response", Response(status_code=502, content=b"Bad Gateway"))
