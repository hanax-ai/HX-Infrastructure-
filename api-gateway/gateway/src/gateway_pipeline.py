# /opt/HX-Infrastructure-/api-gateway/gateway/src/gateway_pipeline.py
import os
import logging
from typing import Any, Dict, List, Optional
from fastapi import Request, Response
from fastapi.responses import JSONResponse
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

logger = logging.getLogger(__name__)


def _load_db_config() -> Dict[str, Optional[str]]:
    """Loads database configuration from environment variables."""
    return {
        'postgres_url': os.getenv("DATABASE_URL"),
        'redis_url': os.getenv("REDIS_URL"),
        'qdrant_url': os.getenv("QDRANT_URL"),
    }


class GatewayPipeline:
    def __init__(self, middlewares: Optional[List[MiddlewareBase]] = None):
        if middlewares is None:
            # Initialize database services
            db_config = _load_db_config()
            
            # Validate required database connections
            if not db_config['postgres_url']:
                raise ValueError("DATABASE_URL environment variable is required but not set")
            if not db_config['redis_url']:
                raise ValueError("REDIS_URL environment variable is required but not set")
            
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
        # ExecutionMiddleware should set the final response. If not, it's a failure.
        fallback_error = {
            "error": {
                "message": "Bad Gateway: The request could not be processed by the upstream service.",
                "type": "gateway_error",
                "code": "bad_gateway"
            }
        }
        return context.get("response", JSONResponse(status_code=502, content=fallback_error))

# ---- HX compat shim: tolerate DBGuard signature changes & guarantee stages ----
try:
    _HX__orig_init = GatewayPipeline.__init__  # type: ignore[attr-defined]
except Exception:
    _HX__orig_init = None

def _HX__safe_init(self, *args, **kwargs):
    import os
    try:
        # Try the original constructor first
        if _HX__orig_init is not None:
            _HX__orig_init(self, *args, **kwargs)
        # If stages got set, we're done
        if getattr(self, "stages", None):
            return
    except TypeError:
        # Will fall back to manual pipeline build below
        pass

    # Manual, safe default pipeline
    from .middlewares.security import SecurityMiddleware
    from .middlewares.validation import ValidationMiddleware
    from .middlewares.transform import TransformMiddleware
    from .middlewares.routing import RoutingMiddleware
    from .middlewares.execution import ExecutionMiddleware

    # Optional DB guard – works with either (db_config) or (db_config, redis, prefixes)
    dbguard = None
    try:
        from .middlewares.db_guard import DBGuardMiddleware
        try:
            # Try new signature
            import redis.asyncio as aioredis
            redis_url = os.environ.get("REDIS_URL")
            redis_client = aioredis.from_url(redis_url) if redis_url else None
            db_config = {}  # keep light; real config service can be wired later
            dbguard = DBGuardMiddleware(db_config, redis_client, [])
        except TypeError:
            # Fallback to legacy signature
            dbguard = DBGuardMiddleware({})
    except ImportError as e:
        logger.error(f"DBGuardMiddleware not available: {e}")
        # Let ImportError propagate - do not silently disable
        raise ImportError(f"Failed to import DBGuardMiddleware: {e}")

    self.stages = [
        SecurityMiddleware(),
        dbguard,
        ValidationMiddleware(),
        TransformMiddleware(),
        RoutingMiddleware(),
        ExecutionMiddleware(),
    ]

GatewayPipeline.__init__ = _HX__safe_init  # type: ignore[attr-defined]
# ---- end HX compat shim ----
