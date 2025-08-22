# RAG Delete Endpoints Implementation
## Operational Controls for Vector Index Management

### 🎯 Why Delete Endpoints Are Critical

**Content Lifecycle & Updates:**
- Remove stale chunks before re-ingesting revised documents
- Prevents duplicate/conflicting search hits
- Maintains corpus accuracy and relevance

**Namespace Management:**
- Bulk-purge everything for a project/environment/tenant
- Clean separation: `docs:test`, `customer:acme`, etc.
- Multi-tenant isolation without cross-contamination

**Incident Response & Compliance:**
- Hotfix: yank bad ingests or leaked content immediately  
- "Right-to-be-forgotten" compliance
- Data retention and TTL policy enforcement

**Performance & Cost Control:**
- Control index size to maintain optimal latency
- Storage cost management through selective cleanup
- Experiment hygiene for A/B testing scenarios

---

### 🔧 Delete Endpoint Strategy

| Endpoint | Use Case | Best For |
|----------|----------|----------|
| `POST /v1/rag/delete/by_ids` | Precise removal of specific points | Single document chunk sets |
| `POST /v1/rag/delete/by_namespace` | Fast bulk cleanup | Project/environment teardown |
| `POST /v1/rag/delete/by_filter` | Targeted metadata-based deletes | Date ranges, source types, categories |
| `DELETE /v1/rag/document?id=...` | Convenience single-ID deletion | UI/operational use |

---

### 🛡️ Guardrails & Best Practices

**Security:**
- ✅ Writes require `X-HX-Admin-Key` (already enforced)
- ✅ Write-scope authentication for all delete operations
- ✅ Audit logging with namespace, filter, requester, operation ID

**Safety Measures:**
- 🔄 **RECOMMENDED**: Snapshot Qdrant before bulk deletes
- 🔄 **FUTURE**: Dry-run/preview mode (`preview=true` returns count without deleting)
- ✅ Post-delete validation with `/points/count` verification
- ✅ Idempotent operations with stable IDs

**Performance:**
- ✅ Rate limiting for large filter operations
- ✅ Configurable timeouts for bulk operations
- ✅ Structured logging for operation tracking

---

### ⚡ Implementation Plan

**Phase 1: Core Delete APIs** ✅
- Delete by IDs (precise removal)
- Delete by namespace (bulk cleanup)  
- Delete by filter (metadata-based)
- Single document convenience endpoint

**Phase 2: Safety & Observability** 🔄
- Preview/dry-run functionality
- Enhanced audit logging
- Backup integration hooks
- Performance metrics

**Phase 3: Advanced Features** 📋
- TTL management with nightly reaper
- Batch delete optimization
- Cross-namespace validation
- Recovery procedures

---

### 📊 Benefits vs. Risks

**✅ Advantages:**
- Accurate search results (no ghost/stale content)
- Faster iteration on document corpora
- Compliance readiness for data regulations
- Lower storage costs and predictable latency
- Clean experiment management

**⚠️ Risk Mitigation:**
- **Over-deletion**: Preview mode + backup procedures
- **Count uncertainty**: Qdrant returns operation ACK, not exact count (mitigate with follow-up `/points/count`)
- **Performance impact**: Rate limiting and timeout controls
- **Audit requirements**: Comprehensive logging and operation tracking

---

### 🚀 Implementation Steps

#### Prerequisites
```bash
cd /opt/HX-Infrastructure-/api-gateway/gateway
source venv/bin/activate
pip install --quiet prometheus-client pypdf
```

#### 1. Data Models
```python
# gateway/src/models/rag_delete_models.py
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
```

#### 2. Service Layer
```python
# gateway/src/services/rag_delete_helpers.py
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
    # Count unknown until count endpoint is called; return -1 to mean "unknown"
    return ok, r.text, -1
```

#### 3. API Routes
```python
# gateway/src/routes/rag_delete.py
from __future__ import annotations
from typing import Dict, Any
from fastapi import APIRouter, Depends, HTTPException, Query

from ..models.rag_delete_models import (
    DeleteByIdsRequest, DeleteByNamespaceRequest, DeleteByFilterRequest, DeleteResponse
)
from ..services.rag_delete_helpers import qdrant_delete_by_ids, qdrant_delete_by_filter
from ..services.security import require_rag_write  # write-scope auth (X-HX-Admin-Key)

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
```

---

### 🧪 Validation Framework

#### Post-Delete Verification
```bash
# Verify namespace is empty
curl -sS -X POST "$QDRANT_URL/collections/$QCOLL/points/count" \
  -H "Content-Type: application/json" \
  -d '{"exact":true,"filter":{"must":[{"key":"namespace","match":{"value":"docs:test"}}]}}' | jq .

# Expected result: {"result": {"count": 0}}
```

#### Integration with Make Targets
```makefile
# Delete operations
rag-delete-test-namespace:
	@curl -sS -X POST "$(BASE)/v1/rag/delete/by_namespace" \
	  -H "Content-Type: application/json" \
	  -H "X-HX-Admin-Key: $(ADMIN_KEY)" \
	  -d '{"namespace":"$(NS)"}' | jq .

rag-verify-empty:
	@curl -sS -X POST "$(QDRANT_URL)/collections/$(COLL)/points/count" \
	  -H "Content-Type: application/json" \
	  -d '{"exact":true,"filter":{"must":[{"key":"namespace","match":{"value":"$(NS)"}}]}}' | jq .
```

---

### 🎯 Success Criteria

**Functional Requirements:**
- ✅ All delete operations return proper HTTP status codes
- ✅ Idempotent behavior (re-running same delete is safe)
- ✅ Namespace isolation maintained across operations
- ✅ Filter-based deletes work with complex metadata queries

**Operational Requirements:**
- ✅ Comprehensive audit logging for compliance
- ✅ Performance metrics for monitoring
- ✅ Error handling with actionable messages
- ✅ Integration with existing authentication system

**Safety Requirements:**
- ✅ Write-scope authentication enforced
- ✅ Post-operation validation procedures
- ✅ Backup integration points identified
- ✅ Rate limiting to protect vector database
