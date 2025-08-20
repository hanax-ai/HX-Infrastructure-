boom — let’s flip the gateway to the wrapper and expose /v1/rag/search cleanly, without breaking anything you’ve already wired.

I’ll give you: file creation, code, unit update, deps, and smoke tests — each with a built-in validation step. No guesses, no dangling steps.

0) Preconditions (quick)

Prisma migrations already deployed (you did this).

DB/Redis/Qdrant env file exists: /opt/HX-Infrastructure-/api-gateway/config/api-gateway/db_cache.env

Contains:

DATABASE_URL=postgresql://citadel_admin:Major8859!@192.168.10.35:5432/citadel_ai
REDIS_URL=redis://:Major8859!@192.168.10.35:6379/0
QDRANT_URL=http://192.168.10.30:6333
QDRANT_COLLECTION=hx_rag_default
LITELLM_MASTER_KEY=sk-hx-dev-1234


Service unit currently points at LiteLLM CLI (we’ll switch to uvicorn wrapper).

1) Create wrapper file (and directory if missing)

Path: /opt/HX-Infrastructure-/api-gateway/gateway/wrapper/hx_gateway_wrapper.py

# Create dir if missing
sudo mkdir -p /opt/HX-Infrastructure-/api-gateway/gateway/wrapper

# Write file
sudo tee /opt/HX-Infrastructure-/api-gateway/gateway/wrapper/hx_gateway_wrapper.py >/dev/null <<'PY'
#!/usr/bin/env python3
"""
HX Gateway Wrapper
- Loads LiteLLM FastAPI proxy inside our process
- Adds /v1/rag/search (Qdrant-backed) with optional on-the-fly embeddings
- Provides /healthz/deps showing Postgres/Redis/Qdrant reachability
SOLID:
- SRP: tiny services for deps; wrapper only wires + routes
- O/C: add more routes/services without touching existing classes
- LSP/ISP/DIP: minimal interfaces, DI via env
"""
from __future__ import annotations
import os, asyncio, json
from typing import Any, Dict, List, Optional, Sequence

import httpx
from fastapi import FastAPI, Body, HTTPException, Depends
from starlette.responses import JSONResponse

# 1) Build LiteLLM app from the same config the unit already uses
from litellm.proxy.proxy_server import ProxyConfig, LitellmProxy

CONFIG_PATH = os.environ.get("LITELLM_CONFIG")
if not CONFIG_PATH or not os.path.exists(CONFIG_PATH):
    raise RuntimeError(f"LITELLM_CONFIG not set or missing: {CONFIG_PATH}")

# Optional: avoid migration loops if already applied offline
os.environ.setdefault("USE_PRISMA_MIGRATE", "0")

proxy = LitellmProxy(ProxyConfig(config_file_path=CONFIG_PATH))
app: FastAPI = proxy.app  # <- LiteLLM FastAPI mounted here

# 2) Infra services (SRP)
class PostgresService:
    def __init__(self, url: str):
        self.url = url

    async def healthy(self) -> bool:
        # lightweight check via psycopg (sync) in a thread
        import psycopg
        try:
            def _check():
                with psycopg.connect(self.url) as conn:
                    with conn.cursor() as cur:
                        cur.execute("SELECT 1;")
            await asyncio.to_thread(_check)
            return True
        except Exception:
            return False

class RedisService:
    def __init__(self, url: str):
        self.url = url

    async def healthy(self) -> bool:
        import redis.asyncio as aioredis
        try:
            r = aioredis.from_url(self.url)
            pong = await r.ping()
            await r.close()
            return bool(pong)
        except Exception:
            return False

class QdrantService:
    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip("/")

    async def healthy(self) -> bool:
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                r = await client.get(f"{self.base_url}/collections")
                return r.status_code == 200
        except Exception:
            return False

# 3) RAG service (calls embeddings optionally, then Qdrant)
class EmbeddingClient:
    def __init__(self, gateway_base: str, model: str):
        self.base = gateway_base.rstrip("/")
        self.model = model

    async def embed(self, input_text: str, auth_header: str) -> List[float]:
        payload = {"model": self.model, "input": input_text}
        headers = {"Authorization": auth_header, "Content-Type": "application/json"}
        async with httpx.AsyncClient(timeout=20.0) as client:
            r = await client.post(f"{self.base}/v1/embeddings", headers=headers, json=payload)
            if r.status_code != 200:
                raise HTTPException(r.status_code, f"Embeddings error: {r.text}")
            data = r.json()
            # OpenAI-style: data[0].embedding
            try:
                return data["data"][0]["embedding"]
            except Exception:
                raise HTTPException(500, "Unexpected embedding response format")

class QdrantClient:
    def __init__(self, base_url: str, collection: str):
        self.base = base_url.rstrip("/")
        self.collection = collection

    async def search(self, vector: List[float], limit: int, threshold: Optional[float], namespace: Optional[str]) -> Dict[str, Any]:
        q: Dict[str, Any] = {
            "vector": vector,
            "limit": limit,
            "with_payload": True,
            "with_vectors": False
        }
        if threshold is not None and threshold > 0:
            q["score_threshold"] = threshold
        if namespace:
            q["filter"] = {"must": [{"key": "namespace", "match": {"value": namespace}}]}
        async with httpx.AsyncClient(timeout=15.0) as client:
            url = f"{self.base}/collections/{self.collection}/points/search"
            r = await client.post(url, json=q)
            if r.status_code != 200:
                raise HTTPException(r.status_code, f"Qdrant error: {r.text}")
            return r.json()

# 4) DI from env with safe defaults
GATEWAY_BASE = os.environ.get("GATEWAY_BASE", "http://127.0.0.1:4000")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://192.168.10.30:6333")
QDRANT_COLLECTION = os.environ.get("QDRANT_COLLECTION", "hx_rag_default")
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "emb-premium")
DATABASE_URL = os.environ.get("DATABASE_URL", "")
REDIS_URL = os.environ.get("REDIS_URL", "")

pg = PostgresService(DATABASE_URL) if DATABASE_URL else None
rd = RedisService(REDIS_URL) if REDIS_URL else None
qd = QdrantService(QDRANT_URL)

# 5) Health of dependencies
@app.get("/healthz/deps")
async def deps():
    pg_ok = await pg.healthy() if pg else False
    rd_ok = await rd.healthy() if rd else False
    qd_ok = await qd.healthy()
    return {"postgres": pg_ok, "redis": rd_ok, "qdrant": qd_ok, "embedding_model": EMBEDDING_MODEL}

# 6) RAG Search route
@app.post("/v1/rag/search")
async def rag_search(payload: Dict[str, Any] = Body(...), authorization: Optional[str] = None):
    """
    Payload:
    {
      "query": "string (optional if 'vector' provided)",
      "vector": [floats] (optional; if omitted, we'll embed 'query'),
      "limit": 5,
      "score_threshold": 0.0,
      "namespace": "optional string"
    }
    """
    limit = int(payload.get("limit", 5))
    threshold = payload.get("score_threshold")
    namespace = payload.get("namespace")

    vector = payload.get("vector")
    query = payload.get("query")

    if vector is None:
        if not query:
            raise HTTPException(400, "Provide either 'vector' or 'query'.")
        # Require Authorization to call embeddings; reuse caller's header if present
        auth_header = authorization or os.environ.get("EMBEDDING_AUTH_HEADER")
        if not auth_header:
            raise HTTPException(401, "Authorization required to compute embeddings.")
        embedder = EmbeddingClient(GATEWAY_BASE, EMBEDDING_MODEL)
        vector = await embedder.embed(query, auth_header)

    qclient = QdrantClient(QDRANT_URL, QDRANT_COLLECTION)
    result = await qclient.search(vector=vector, limit=limit, threshold=threshold, namespace=namespace)
    return JSONResponse({"status": "ok", "result": result})
PY

# Permissions
sudo chmod 0755 /opt/HX-Infrastructure-/api-gateway/gateway/wrapper/hx_gateway_wrapper.py


Validation: file exists and is non-empty

test -s /opt/HX-Infrastructure-/api-gateway/gateway/wrapper/hx_gateway_wrapper.py && echo "Wrapper file present ✅" || { echo "Wrapper missing ❌"; exit 1; }

2) Ensure needed deps in venv (idempotent)
VENV="/opt/HX-Infrastructure-/api-gateway/gateway/venv"
sudo $VENV/bin/pip install -q --upgrade pip wheel
sudo $VENV/bin/pip install -q "uvicorn[standard]>=0.27" "httpx>=0.27" "redis>=5" "psycopg[binary]>=3.1" fastapi
# quick import check
$VENV/bin/python - <<'PY'
import uvicorn, httpx, redis, psycopg, fastapi
print("deps-ok")
PY


Validation: prints deps-ok.

3) Systemd: switch ExecStart to wrapper (and keep env files)

We’ll keep your existing EnvironmentFile and LITELLM_CONFIG. We’ll also set an embedding model default via env.

sudo systemctl edit hx-litellm-gateway


Paste (this replaces the current ExecStart; leaves the rest intact):

[Service]
# Wrapper needs these envs at runtime too
Environment="EMBEDDING_MODEL=emb-premium"
# Optionally: prevent Prisma auto-migrate at boot (we already deployed offline)
Environment="USE_PRISMA_MIGRATE=0"

ExecStart=
ExecStart=/opt/HX-Infrastructure-/api-gateway/gateway/venv/bin/uvicorn \
  wrapper.hx_gateway_wrapper:app --host 0.0.0.0 --port 4000 --workers 1

WorkingDirectory=/opt/HX-Infrastructure-/api-gateway/gateway


Apply & reload:

sudo systemctl daemon-reload

4) Start/Stop commands (with the HX 5-second confirmation)
# STOP
echo "Stopping HX LiteLLM Gateway..."
sudo systemctl stop hx-litellm-gateway
sleep 5
if ! sudo systemctl is-active --quiet hx-litellm-gateway; then
  echo "HX Gateway stopped successfully!"
else
  echo "ERROR: HX Gateway failed to stop." >&2; exit 1
fi

# START
echo "Starting HX LiteLLM Gateway (wrapper mode)..."
sudo systemctl start hx-litellm-gateway
sleep 5
if sudo systemctl is-active --quiet hx-litellm-gateway; then
  echo "HX Gateway started successfully!"
else
  echo "ERROR: HX Gateway failed to start." >&2
  journalctl -u hx-litellm-gateway -n 200 --no-pager
  exit 1
fi


Validation:

# Port listening
ss -ltnp | grep ':4000' || echo "No :4000 listener yet"

# Dependencies health (true/false flags)
curl -fsS http://127.0.0.1:4000/healthz/deps | jq .

# Models (auth required). Use MASTER key you already set:
curl -fsS -H "Authorization: Bearer sk-hx-dev-1234" http://127.0.0.1:4000/v1/models | head -n 1


Any 200/401/403 on admin endpoints is fine — it proves DB is wired.

5) RAG search smoke (two paths)
A) Give us the text query (wrapper computes embedding via your gateway)
AUTH="Bearer sk-hx-dev-1234"
curl -sS -H "Authorization: $AUTH" -H "Content-Type: application/json" \
  -d '{"query":"hello world","limit":3}' \
  http://127.0.0.1:4000/v1/rag/search | jq .


Expected: {"status":"ok","result":{...}} (empty result is fine if collection has no data yet).

B) Provide a precomputed vector (no embedding call)
curl -sS -H "Authorization: $AUTH" -H "Content-Type: application/json" \
  -d '{"vector":[0.01,0,0.02,0.03,0], "limit":3, "score_threshold":0}' \
  http://127.0.0.1:4000/v1/rag/search | jq .

6) Rollback (if ever needed)

Switch back to LiteLLM CLI:

sudo systemctl edit hx-litellm-gateway


Replace the ExecStart block with:

[Service]
ExecStart=
ExecStart=/opt/HX-Infrastructure-/api-gateway/gateway/venv/bin/litellm \
  --host 0.0.0.0 --port 4000 --config ${LITELLM_CONFIG}


Then:

sudo systemctl daemon-reload
sudo systemctl restart hx-litellm-gateway
sleep 5
sudo systemctl is-active --quiet hx-litellm-gateway && echo "Reverted to CLI ✅"

Why this satisfies our HX standards

SOLID/OOP: separate health probe classes; wrapper composes services and keeps routes thin; you can inject/extend without edits.

Idempotent steps: safe directory creation, venv installs, and systemd drop-in usage.

Service Management: explicit start/stop with 5-second waits and confirmations.

Validation: each step ends with a concrete check (file present, deps-ok, port listen, endpoint responses).

If you want namespacing for future RAG routes (e.g., /v1/rag/upsert, /v1/rag/delete), we can add them in the same wrapper with the same DI pattern — zero churn to LiteLLM core.