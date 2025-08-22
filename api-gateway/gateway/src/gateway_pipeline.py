# /opt/HX-Infrastructure-/api-gateway/gateway/src/gateway_pipeline.py
import logging
import os
from typing import Any, Optional

from fastapi import Request, Response
from fastapi.responses import JSONResponse

from .middlewares.base import MiddlewareBase
from .middlewares.db_guard import DBGuardMiddleware
from .middlewares.execution import ExecutionMiddleware
from .middlewares.routing import RoutingMiddleware
from .middlewares.security import SecurityMiddleware
from .middlewares.transform import TransformMiddleware
from .middlewares.validation import ValidationMiddleware

logger = logging.getLogger(__name__)


def _load_db_config() -> dict[str, Optional[str]]:
    """Loads database configuration from environment variables."""
    return {
        "postgres_url": os.getenv("DATABASE_URL"),
        "redis_url": os.getenv("REDIS_URL"),
        "qdrant_url": os.getenv("QDRANT_URL"),
    }


class GatewayPipeline:
    def __init__(self, middlewares: Optional[list[MiddlewareBase]] = None):
        if middlewares is None:
            # Initialize database services
            db_config = _load_db_config()

            # Allow tests/lightweight runs to skip DB by default.
            # Set STRICT_DB=1 in prod to force hard failure.
            strict_db = os.getenv("STRICT_DB", "0").lower() in ("1", "true", "yes")
            if not db_config.get("postgres_url"):
                if strict_db:
                    raise ValueError(
                        "DATABASE_URL environment variable is required but not set"
                    )
                import logging

                logging.getLogger(__name__).warning(
                    "DATABASE_URL not set; continuing without DB. DB-backed features disabled."
                )
                self._db_enabled = False
            else:
                self._db_enabled = True

            # Validate Redis URL if DB is enabled
            if self._db_enabled and not db_config["redis_url"]:
                if strict_db:
                    raise ValueError(
                        "REDIS_URL environment variable is required but not set"
                    )
                logging.getLogger(__name__).warning(
                    "REDIS_URL not set; some features may be limited."
                )

            # Create DB-Guard middleware with service configuration
            # Pass db_enabled flag to middleware so it can handle missing DB gracefully
            db_config["_db_enabled"] = self._db_enabled
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
        context: dict[str, Any] = {"request": request, "response": None}
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
                "code": "bad_gateway",
            }
        }
        return context.get(
            "response", JSONResponse(status_code=502, content=fallback_error)
        )


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
    from .middlewares.execution import ExecutionMiddleware
    from .middlewares.routing import RoutingMiddleware
    from .middlewares.security import SecurityMiddleware
    from .middlewares.transform import TransformMiddleware
    from .middlewares.validation import ValidationMiddleware

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
