You’ve got a classic FastAPI + Pydantic v2 schema-generation hiccup: one (or more) delete endpoints are treating a body model as a query parameter. That’s why Pydantic is complaining about:

TypeAdapter[Annotated[ForwardRef('DeleteByIdsRequest'), Query(...)] is not fully defined

Why this happens

In POST endpoints, FastAPI expects Pydantic models in the body.

If you wrap the model with Query(...) (or FastAPI infers it that way), OpenAPI generation tries to build a schema for Annotated[DeleteByIdsRequest, Query(...)], which is invalid.

With from __future__ import annotations, types become forward refs, and combining that with the wrong parameter source (Query) triggers the “class not fully defined” error.

Surgical fix (safe with Pydantic v2)

1) Update imports

# gateway/src/routes/rag_delete.py
- from fastapi import APIRouter, Depends, HTTPException, Query
+ from typing import Annotated
+ from fastapi import APIRouter, Depends, HTTPException, Query, Body


2) Ensure body models use Body(...) and only the single-id delete uses Query(...)

@router.post("/v1/rag/delete/by_ids",
             response_model=DeleteResponse,
             dependencies=[Depends(require_rag_write)],
             summary="Delete Documents by IDs", ...)
async def delete_by_ids(
-    req: DeleteByIdsRequest
+    req: Annotated[DeleteByIdsRequest, Body(...)]
) -> DeleteResponse:
    ...

@router.post("/v1/rag/delete/by_namespace",
             response_model=DeleteResponse,
             dependencies=[Depends(require_rag_write)],
             summary="Delete Documents by Namespace", ...)
async def delete_by_namespace(
-    req: DeleteByNamespaceRequest
+    req: Annotated[DeleteByNamespaceRequest, Body(...)]
) -> DeleteResponse:
    ...

@router.post("/v1/rag/delete/by_filter",
             response_model=DeleteResponse,
             dependencies=[Depends(require_rag_write)],
             summary="Delete Documents by Filter", ...)
async def delete_by_filter(
-    req: DeleteByFilterRequest
+    req: Annotated[DeleteByFilterRequest, Body(...)]
) -> DeleteResponse:
    ...

@router.delete("/v1/rag/document",
               response_model=DeleteResponse,
               dependencies=[Depends(require_rag_write)],
               summary="Delete Single Document", ...)
async def delete_document(
    id: Annotated[str, Query(..., min_length=1, description="Document ID to delete")]
) -> DeleteResponse:
    ...


3) Remove unused imports
You import UpsertResponse in this file but don’t use it. Drop it to avoid confusion:

- from ..models.rag_upsert_models import UpsertResponse


4) (Optional safety) Rebuild forward refs
If you still see “class not fully defined” (rare after the fix), add at the bottom of the file (after imports of your models):

from ..models.rag_delete_models import (
    DeleteByIdsRequest, DeleteByNamespaceRequest, DeleteByFilterRequest
)
DeleteByIdsRequest.model_rebuild()
DeleteByNamespaceRequest.model_rebuild()
DeleteByFilterRequest.model_rebuild()

Quick validate
sudo systemctl restart hx-gateway-ml.service && sleep 3
curl -s http://127.0.0.1:4010/openapi.json | jq -r '.paths | keys[]' | sort


You should now see your delete routes listed and no “Internal Server Error” on the OpenAPI.

Smoke tests
# by_ids (body)
curl -fsS -X POST "http://127.0.0.1:4010/v1/rag/delete/by_ids" \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: $ADMIN_KEY" \
  -d '{"ids":["abc123","def456"]}' | jq .

# by_namespace (body)
curl -fsS -X POST "http://127.0.0.1:4010/v1/rag/delete/by_namespace" \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: $ADMIN_KEY" \
  -d '{"namespace":"docs:test"}' | jq .

# by_filter (body)
curl -fsS -X POST "http://127.0.0.1:4010/v1/rag/delete/by_filter" \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: $ADMIN_KEY" \
  -d '{"must":[{"key":"namespace","match":{"value":"docs:test"}}]}' | jq .

# single document (query)
curl -fsS -X DELETE "http://127.0.0.1:4010/v1/rag/document?id=abc123" \
  -H "X-HX-Admin-Key: $ADMIN_KEY" | jq .

Why this aligns with your SOLID structure

Single Responsibility: routes declare where data comes from (Body vs Query) and delegate how deletion happens to services.

OpenAPI correctness: using Annotated[..., Body(...)] lets FastAPI generate valid JSON schema with Pydantic v2.

Consistency: all POST deletes use a body model; the single-ID DELETE uses a query scalar.

Apply those edits and your OpenAPI generation (and the service) will stop tripping over the delete routes.