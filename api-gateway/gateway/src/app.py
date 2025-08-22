# gateway/src/app.py
from fastapi import FastAPI, Request
from starlette.responses import JSONResponse, Response

from .gateway_pipeline import GatewayPipeline

# Routers
from .routes.rag import router as rag_router
from .routes.rag_content_loader import router as rag_loader_router
from .routes.rag_delete import router as rag_delete_router
from .routes.rag_upsert import router as rag_upsert_router


def build_app() -> FastAPI:
    app = FastAPI(title="HX API Gateway")
    pipeline = GatewayPipeline()

    # Mount all RAG routers explicitly
    app.include_router(rag_router, tags=["rag"])
    app.include_router(rag_upsert_router, tags=["rag"])
    app.include_router(rag_delete_router, tags=["rag"])
    app.include_router(rag_loader_router, tags=["rag"])

    @app.get("/healthz")
    async def healthz():
        return {"ok": True}

    # Keep the catch-all proxy last
    @app.api_route(
        "/{path:path}",
        methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        include_in_schema=False,
    )
    async def _all(request: Request, path: str) -> Response:
        resp: Response | None = await pipeline.process_request(request)
        return resp or JSONResponse({"detail": "Not Found"}, status_code=404)

    return app
