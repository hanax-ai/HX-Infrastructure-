3) Metrics stub (/metrics, plus basic counters)
3.1 Metrics module
sudo tee gateway/src/metrics.py >/dev/null <<'PY'
from __future__ import annotations
from prometheus_client import Counter, Histogram

rag_upserts = Counter("rag_upserts_total", "Total RAG upsert requests", ["result"])
rag_deletes = Counter("rag_deletes_total", "Total RAG delete requests", ["result", "mode"])
rag_search  = Counter("rag_search_total",  "Total RAG search requests",  ["result", "path"])

embed_latency = Histogram("rag_embedding_seconds", "Embedding call latency (s)")
qdrant_latency = Histogram("rag_qdrant_seconds", "Qdrant call latency (s)", ["op"])
PY

3.2 Wire /metrics in app factory
sudo sed -i '1s|^|import os\n|' gateway/src/app.py
sudo sed -i 's/from fastapi import FastAPI, Request/from fastapi import FastAPI, Request, Response/' gateway/src/app.py
sudo sed -i 's/from starlette.responses import JSONResponse, Response/from starlette.responses import JSONResponse, Response as StarResponse/' gateway/src/app.py

# Add imports for metrics + routers and /metrics endpoint (idempotent)
sudo awk -i inplace '
/def build_app\(\) -> FastAPI:/ && c==0 {print; print "    from prometheus_client import generate_latest, CONTENT_TYPE_LATEST"; c=1; next} {print}
' gateway/src/app.py

# Ensure we include new routers (delete + loader)
sudo awk -i inplace '
/app = FastAPI\(title="HX API Gateway"\)/ && c==0 {print; print "    from .routes.rag_delete import router as rag_delete_router"; print "    from .routes.rag_loader import router as rag_loader_router"; c=1; next} {print}
' gateway/src/app.py

sudo awk -i inplace '
/app.include_router\(rag_router, tags=\["rag"\]\)/ && c==0 {print "    app.include_router(rag_delete_router, tags=[\"rag\"])"; print "    app.include_router(rag_loader_router, tags=[\"rag\"])"; print; c=1; next} {print}
' gateway/src/app.py

# Add /metrics endpoint near /healthz (idempotent)
sudo awk -i inplace '
/@app.get\(\"\/healthz\"\)/ && c==0 {print; print "    @app.get(\"/metrics\")"; print "    async def metrics():\n        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)"; c=1; next} {print}
' gateway/src/app.py


If your awk edits don’t apply due to layout variations, I can provide a direct patched app.py. The intent: import routers, include them, and add /metrics.