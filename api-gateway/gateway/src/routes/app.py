from ..models.rag_upsert_models import UpsertResponse
# gateway/src/app.py
import os
from fastapi import File, UploadFile, Form, FastAPI, Request
from starlette.responses import JSONResponse, Response
from .gateway_pipeline import GatewayPipeline
from .routers.rag import router as rag_router

def build_app() -> FastAPI:
    app = FastAPI(title="HX API Gateway")
    pipeline = GatewayPipeline()

    # Mount specific routers first
    app.include_router(rag_router, tags=["rag"])

    @app.get("/healthz")
    async def healthz():
        return {"ok": True}

    # Catch-all proxy stays last
    @app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"])
    async def _all(request: Request, path: str) -> Response:
        resp: Response | None = await pipeline.process_request(request)
        return resp or JSONResponse({"detail": "Not Found"}, status_code=404)

    return app