Fast hardening wins (do these next)

Namespace hygiene (Qdrant)

# index common payload fields for faster filters
curl -sS -X PUT "$QDRANT_URL/collections/$QDRANT_COLLECTION/index" \
  -H 'Content-Type: application/json' \
  -d '{"field_name":"namespace","field_schema":"keyword"}'

curl -sS -X PUT "$QDRANT_URL/collections/$QDRANT_COLLECTION/index" \
  -H 'Content-Type: application/json' \
  -d '{"field_name":"doc_id","field_schema":"keyword"}'


Validate: count by filter returns instantly:

curl -sS -X POST "$QDRANT_URL/collections/$QDRANT_COLLECTION/points/count" \
  -H 'Content-Type: application/json' \
  -d '{"exact":true,"filter":{"must":[{"key":"namespace","match":{"value":"test:loader"}}]}}' | jq .


Tiny retention lever (TTL)

Add a expires_at (int timestamp) payload on ingest.

Nightly cron deletes {"should":[{"key":"expires_at","range":{"lt":<now>}}]} (see delete endpoints below).
Validate: delete-by-filter reduces count to 0 (command at the end).

Observability

Log per-request: op, namespace, doc_count, latency_ms.

Export a basic /metrics FastAPI route later; for now ensure journald shows op summaries.
Validate: journalctl -u hx-gateway-ml.service | tail shows structured lines.

Makefile convenience (shortcuts your validations)

rag-list:
\t@curl -s http://127.0.0.1:4010/openapi.json | jq -r '.paths | keys[]' | sort
rag-upsert-md:
\t@curl -sS -X POST "http://127.0.0.1:4010/v1/rag/upsert_markdown" \
\t  -H "Content-Type: application/json" -H "X-HX-Admin-Key: $${HX_ADMIN_KEY}" \
\t  -d '{"text":"# HX Doc\\nhello","namespace":"docs:demo","chunk_chars":600,"overlap":80}' | jq .
rag-search:
\t@curl -sS -X POST "http://127.0.0.1:4010/v1/rag/search" \
\t  -H "Content-Type: application/json" \
\t  -d '{"query":"hello","limit":3,"namespace":"docs:demo"}' | jq .


Validate: make rag-list rag-upsert-md rag-search → returns “ok” and at least one result.

Add DELETE endpoints (precise, bulk, and filtered)
1) Models (SOLID: models only define shape)

gateway/src/models/rag_delete_models.py

from __future__ import annotations
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field, ConfigDict

class DeleteByIdsRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    ids: List[str] = Field(..., min_length=1, description="Point IDs to delete")

class DeleteByNamespaceRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    namespace: str = Field(..., min_length=1)

class DeleteByFilterRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    qdrant_filter: Dict[str, Any] = Field(..., description="Qdrant filter JSON")

class DeleteResponse(BaseModel):
    status: str
    acknowledged: bool
    details: Optional[Dict[str, Any]] = None

2) Services (SOLID: helpers isolate external calls)

gateway/src/services/rag_delete_helpers.py

from __future__ import annotations
import os, httpx
from typing import Any, Dict, List, Tuple

QDRANT_URL        = os.environ.get("QDRANT_URL", "http://192.168.10.30:6333").rstrip("/")
QDRANT_COLLECTION = os.environ.get("QDRANT_COLLECTION", "hx_rag_default")

async def qdrant_delete_by_ids(ids: List[str]) -> Tuple[bool, str]:
    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points/delete"
    body = {"points": ids}
    async with httpx.AsyncClient(timeout=30.0) as c:
        r = await c.post(url, json=body)
    return (r.status_code == 200, r.text)

async def qdrant_delete_by_filter(qdrant_filter: Dict[str, Any]) -> Tuple[bool, str]:
    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points/delete"
    body = {"filter": qdrant_filter}
    async with httpx.AsyncClient(timeout=60.0) as c:
        r = await c.post(url, json=body)
    return (r.status_code == 200, r.text)

def ns_filter(ns: str) -> Dict[str, Any]:
    return {"must": [{"key": "namespace", "match": {"value": ns}}]}

3) Routes (SOLID: controller + auth only)

gateway/src/routes/rag_delete.py

from __future__ import annotations
from fastapi import APIRouter, Depends
from ..security import require_rag_write
from ..models.rag_delete_models import (
    DeleteByIdsRequest, DeleteByNamespaceRequest, DeleteByFilterRequest, DeleteResponse
)
from ..services.rag_delete_helpers import qdrant_delete_by_ids, qdrant_delete_by_filter, ns_filter

router = APIRouter(tags=["rag"])

@router.post("/v1/rag/delete/by_ids", response_model=DeleteResponse, dependencies=[Depends(require_rag_write)])
async def delete_by_ids(req: DeleteByIdsRequest) -> DeleteResponse:
    ok, msg = await qdrant_delete_by_ids(req.ids)
    return DeleteResponse(status="ok" if ok else "error", acknowledged=ok, details={"raw": msg[:500]})

@router.post("/v1/rag/delete/by_namespace", response_model=DeleteResponse, dependencies=[Depends(require_rag_write)])
async def delete_by_namespace(req: DeleteByNamespaceRequest) -> DeleteResponse:
    ok, msg = await qdrant_delete_by_filter(ns_filter(req.namespace))
    return DeleteResponse(status="ok" if ok else "error", acknowledged=ok, details={"raw": msg[:500]})

@router.post("/v1/rag/delete/by_filter", response_model=DeleteResponse, dependencies=[Depends(require_rag_write)])
async def delete_by_filter(req: DeleteByFilterRequest) -> DeleteResponse:
    ok, msg = await qdrant_delete_by_filter(req.qdrant_filter)
    return DeleteResponse(status="ok" if ok else "error", acknowledged=ok, details={"raw": msg[:500]})

4) Register router
# Import + include (idempotent)
grep -q "routes.rag_delete" gateway/src/app.py || \
  sed -i '1,20 s|from \.routes\.rag import router as rag_router|from .routes.rag import router as rag_router\nfrom .routes.rag_delete import router as rag_delete_router|' gateway/src/app.py

grep -q "rag_delete_router" gateway/src/app.py || \
  sed -i 's/app\.include_router(rag_upsert_router, tags=\["rag"\])\n    app\.include_router(rag_router, tags=\["rag"\])/app.include_router(rag_upsert_router, tags=["rag"])\n    app.include_router(rag_delete_router, tags=["rag"])\n    app.include_router(rag_router, tags=["rag"])/' gateway/src/app.py

5) Restart service (with 5s wait + confirmation)
sudo systemctl stop hx-gateway-ml.service; sleep 5; echo "HX Gateway stopped successfully!"
sudo systemctl start hx-gateway-ml.service; sleep 5; echo "HX Gateway started successfully!"
ss -lntp | grep ':4010 ' && echo "Listening on :4010"

6) Validate endpoints

Presence

curl -s http://127.0.0.1:4010/openapi.json | jq -r '.paths | keys[]' | grep '/v1/rag/delete' | sort


By namespace (expect 200 + acknowledged)

curl -sS -X POST http://127.0.0.1:4010/v1/rag/delete/by_namespace \
  -H "Content-Type: application/json" -H "X-HX-Admin-Key: sk-hx-admin-dev-2024" \
  -d '{"namespace":"docs:demo"}' | jq .


Verify count = 0

curl -sS -X POST "$QDRANT_URL/collections/$QDRANT_COLLECTION/points/count" \
  -H 'Content-Type: application/json' \
  -d '{"exact":true,"filter":{"must":[{"key":"namespace","match":{"value":"docs:demo"}}]}}' | jq .


By ids (smoke)
(Upsert a doc, note its id from the payload or use your stable hash_id logic, then:)

curl -sS -X POST http://127.0.0.1:4010/v1/rag/delete/by_ids \
  -H "Content-Type: application/json" -H "X-HX-Admin-Key: sk-hx-admin-dev-2024" \
  -d '{"ids":["<POINT_ID>"]}' | jq .


By filter (TTL example)

NOW=$(date +%s)
curl -sS -X POST http://127.0.0.1:4010/v1/rag/delete/by_filter \
  -H "Content-Type: application/json" -H "X-HX-Admin-Key: sk-hx-admin-dev-2024" \
  -d "{\"qdrant_filter\":{\"must\":[{\"key\":\"expires_at\",\"range\":{\"lt\":$NOW}}]}}" | jq .

Optional polish (low effort, high value)

Dry-run mode for deletes: add preview=true flag to endpoints that uses /points/count instead of deleting.

Idempotency key on upserts (header Idempotency-Key) → store in payload; skip if already present.

Source-of-truth loader CLI: directory walker that calls /upsert_* and writes a manifest (great for backfills).

Basic rate limits on writes (per admin key) to protect Qdrant during bulk loads.