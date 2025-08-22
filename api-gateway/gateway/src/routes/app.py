# gateway/src/routes/app.py
import logging

from fastapi import FastAPI, HTTPException, Request
from starlette.responses import JSONResponse, Response

from ..gateway_pipeline import GatewayPipeline
from .rag import router as rag_router

logger = logging.getLogger(__name__)


def build_app() -> FastAPI:
    app = FastAPI(title="HX API Gateway")
    pipeline = GatewayPipeline()

    # Mount specific routers first
    app.include_router(rag_router, tags=["rag"])

    @app.get("/healthz")
    async def healthz():
        return {"ok": True}

    # Catch-all proxy stays last
    @app.api_route(
        "/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    )
    async def _all(request: Request, path: str) -> Response:
        try:
            resp: Response | None = await pipeline.process_request(request)
            return resp or JSONResponse({"detail": "Not Found"}, status_code=404)
        except HTTPException:
            # Re-raise HTTP exceptions to preserve status codes and error details
            raise
        except Exception as e:
            # Log full exception with stack trace for debugging
            logger.exception(
                f"Unexpected error processing request {request.method} {path}: {e}"
            )
            # Return minimal error response to avoid exposing internal details
            return JSONResponse({"detail": "Internal Server Error"}, status_code=500)

    return app
