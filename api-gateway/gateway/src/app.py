# gateway/src/app.py
from fastapi import FastAPI, Request
from starlette.responses import JSONResponse, Response
from .gateway_pipeline import GatewayPipeline

def build_app() -> FastAPI:
    app = FastAPI(title="HX API Gateway")
    pipeline = GatewayPipeline()

    @app.get("/healthz")
    async def healthz():
        return {"ok": True}

    @app.api_route("/{full_path:path}", methods=["GET","POST","PUT","PATCH","DELETE","OPTIONS"])
    async def _all(request: Request, full_path: str):
        resp: Response | None = await pipeline.process_request(request)
        return resp or JSONResponse({"detail": "Not Found"}, status_code=404)

    return app