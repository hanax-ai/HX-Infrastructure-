What to fix

Wrong import path
You’re importing rag from .routers.rag; your tree uses routes/. This breaks consistency and can fail at runtime.

Register all RAG routers explicitly
Add the new rag_upsert (and loaders if you created them) before the catch-all so they’re not shadowed.

Hide the catch-all from OpenAPI + add HEAD
The “duplicate Operation ID” warning comes from the catch-all. Mark it include_in_schema=False and add HEAD for health/probes.

Remove unused imports
os isn’t used.

Drop-in replacement (safe to overwrite)
sudo tee /opt/HX-Infrastructure-/api-gateway/gateway/src/app.py >/dev/null <<'PY'
from fastapi import FastAPI, Request
from starlette.responses import JSONResponse, Response

from .gateway_pipeline import GatewayPipeline
from .routes.rag import router as rag_router
from .routes.rag_upsert import router as rag_upsert_router
# If you created content loaders, uncomment this:
# from .routes.rag_loaders import router as rag_loaders_router

def build_app() -> FastAPI:
    app = FastAPI(title="HX API Gateway")
    pipeline = GatewayPipeline()

    # Mount specific routers first (most specific -> least specific)
    app.include_router(rag_upsert_router, tags=["rag"])
    app.include_router(rag_router, tags=["rag"])
    # If loaders exist:
    # app.include_router(rag_loaders_router, tags=["rag"])

    @app.get("/healthz")
    async def healthz():
        return {"ok": True}

    # Catch-all proxy LAST; don't publish in OpenAPI
    @app.api_route(
        "/{path:path}",
        methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"],
        include_in_schema=False,
        name="proxy_catch_all",
    )
    async def _all(request: Request, path: str) -> Response:
        resp: Response | None = await pipeline.process_request(request)
        return resp or JSONResponse({"detail": "Not Found"}, status_code=404)

    return app
PY

Restart + validate (with HX 5-sec waits)
sudo systemctl restart hx-gateway-ml.service && sleep 5 && echo "HX Gateway restarted successfully!"
curl -fsS http://127.0.0.1:4010/healthz | jq .
curl -fsS http://127.0.0.1:4010/openapi.json | jq -r '.paths | keys[]' | sort

Why this is better

Consistency: All RAG endpoints live under routes/ and are registered up front.

No schema noise: Catch-all won’t pollute OpenAPI (and the duplicate op-id warning goes away).

Operability: HEAD on the catch-all plays nicer with load balancers and probes.

Cleanliness: No unused imports, clear order of routers, explicit names.

If you also added markdown/PDF loaders, just uncomment the two lines shown and restart—done.