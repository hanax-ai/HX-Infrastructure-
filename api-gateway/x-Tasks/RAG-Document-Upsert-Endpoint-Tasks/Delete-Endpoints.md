0) Prereqs (libs)
cd /opt/HX-Infrastructure-/api-gateway/gateway
source venv/bin/activate
pip install --quiet prometheus-client pypdf

1) DELETE APIs (by id, by namespace, by filter)
1.1 Models
sudo mkdir -p gateway/src/models && sudo touch gateway/src/models/__init__.py
sudo tee gateway/src/models/rag_delete_models.py >/dev/null <<'PY'
from __future__ import annotations
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field, ConfigDict

class DeleteByIdsRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    ids: List[str] = Field(..., min_length=1, description="Point IDs to delete")

class DeleteByNamespaceRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    namespace: str = Field(..., min_length=1, description="Namespace to delete")

class DeleteByFilterRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    must: Optional[List[Dict[str, Any]]] = None
    should: Optional[List[Dict[str, Any]]] = None
    must_not: Optional[List[Dict[str, Any]]] = None

class DeleteResponse(BaseModel):
    status: str
    deleted: int
    detail: Optional[str] = None
PY

1.2 Services
sudo mkdir -p gateway/src/services && sudo touch gateway/src/services/__init__.py
sudo tee gateway/src/services/rag_delete_helpers.py >/dev/null <<'PY'
from __future__ import annotations
import os
from typing import Any, Dict, List, Optional, Tuple
import httpx

QDRANT_URL        = os.environ.get("QDRANT_URL", "http://192.168.10.30:6333").rstrip("/")
QDRANT_COLLECTION = os.environ.get("QDRANT_COLLECTION", "hx_rag_default")

async def qdrant_delete_by_ids(ids: List[str]) -> Tuple[bool, str, int]:
    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points/delete"
    body = {"points": ids}
    async with httpx.AsyncClient(timeout=20.0) as client:
        r = await client.post(url, json=body)
    ok = r.status_code == 200
    # Qdrant returns operation id, not count; we pessimistically return len(ids) on success
    return ok, r.text, len(ids) if ok else 0

async def qdrant_delete_by_filter(qfilter: Dict[str, Any]) -> Tuple[bool, str, int]:
    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points/delete"
    body = {"filter": qfilter}
    async with httpx.AsyncClient(timeout=30.0) as client:
        r = await client.post(url, json=body)
    ok = r.status_code == 200
    # Count unknown until count endpoint is called; return -1 to mean “unknown”
    return ok, r.text, -1
PY

1.3 Routes
sudo mkdir -p gateway/src/routes && sudo touch gateway/src/routes/__init__.py
sudo tee gateway/src/routes/rag_delete.py >/dev/null <<'PY'
from __future__ import annotations
from typing import Dict, Any
from fastapi import APIRouter, Depends, HTTPException, Query

from ..models.rag_delete_models import (
    DeleteByIdsRequest, DeleteByNamespaceRequest, DeleteByFilterRequest, DeleteResponse
)
from ..services.rag_delete_helpers import qdrant_delete_by_ids, qdrant_delete_by_filter
from .security import require_rag_write  # write-scope auth (X-HX-Admin-Key)

router = APIRouter(tags=["rag"])

@router.post("/v1/rag/delete/by_ids", response_model=DeleteResponse, dependencies=[Depends(require_rag_write)])
async def delete_by_ids(req: DeleteByIdsRequest) -> DeleteResponse:
    ok, msg, n = await qdrant_delete_by_ids(req.ids)
    if not ok:
        raise HTTPException(502, f"Qdrant delete_by_ids failed: {msg[:300]}")
    return DeleteResponse(status="ok", deleted=n)

@router.post("/v1/rag/delete/by_namespace", response_model=DeleteResponse, dependencies=[Depends(require_rag_write)])
async def delete_by_namespace(req: DeleteByNamespaceRequest) -> DeleteResponse:
    qfilter: Dict[str, Any] = {"must": [{"key": "namespace", "match": {"value": req.namespace}}]}
    ok, msg, n = await qdrant_delete_by_filter(qfilter)
    if not ok:
        raise HTTPException(502, f"Qdrant delete_by_namespace failed: {msg[:300]}")
    return DeleteResponse(status="ok", deleted=n, detail="count unknown; use /points/count to verify")

@router.post("/v1/rag/delete/by_filter", response_model=DeleteResponse, dependencies=[Depends(require_rag_write)])
async def delete_by_filter(req: DeleteByFilterRequest) -> DeleteResponse:
    qfilter = {}
    if req.must: qfilter["must"] = req.must
    if req.should: qfilter["should"] = req.should
    if req.must_not: qfilter["must_not"] = req.must_not
    if not qfilter:
        raise HTTPException(400, "Provide at least one of: must, should, must_not")
    ok, msg, n = await qdrant_delete_by_filter(qfilter)
    if not ok:
        raise HTTPException(502, f"Qdrant delete_by_filter failed: {msg[:300]}")
    return DeleteResponse(status="ok", deleted=n, detail="count unknown; use /points/count to verify")

# Convenience: single-id delete via query param
@router.delete("/v1/rag/document", response_model=DeleteResponse, dependencies=[Depends(require_rag_write)])
async def delete_document(id: str = Query(..., min_length=1)) -> DeleteResponse:
    ok, msg, n = await qdrant_delete_by_ids([id])
    if not ok:
        raise HTTPException(502, f"Qdrant delete_document failed: {msg[:300]}")
    return DeleteResponse(status="ok", deleted=n)
PY

Minimal validation step (each delete)

Call delete endpoint.

Immediately verify with Qdrant:

curl -sS -X POST "$QDRANT_URL/collections/$QCOLL/points/count" \
  -H "Content-Type: application/json" \
  -d '{"exact":true,"filter":{"must":[{"key":"namespace","match":{"value":"docs:test"}}]}}' | jq .


Confirm count is 0 (or expected number).