You’re hitting an OpenAPI-generation crash because one of your delete endpoints is (still) mixing a body model with Query(...). The traceback shows Pydantic trying to build a schema for:

Annotated[ForwardRef('Annotated[DeleteByIdsRequest, Body(...)]'), Query(...)]


…which means that parameter ended up with both Body(...) and Query(...) applied. FastAPI + Pydantic v2 can’t resolve that, so /openapi.json returns 500.

Here’s the tight, safe fix.

What to change (minimal + SOLID-friendly)
1) Make POST delete endpoints take their models in the body (no Query)

In gateway/src/routes/rag_delete.py, ensure these signatures look like this (no Annotated[...], no Query):

@router.post("/v1/rag/delete/by_ids", response_model=DeleteResponse, dependencies=[Depends(require_rag_write)])
async def delete_by_ids(req: DeleteByIdsRequest) -> DeleteResponse:
    ...

@router.post("/v1/rag/delete/by_namespace", response_model=DeleteResponse, dependencies=[Depends(require_rag_write)])
async def delete_by_namespace(req: DeleteByNamespaceRequest) -> DeleteResponse:
    ...

@router.post("/v1/rag/delete/by_filter", response_model=DeleteResponse, dependencies=[Depends(require_rag_write)])
async def delete_by_filter(req: DeleteByFilterRequest) -> DeleteResponse:
    ...


FastAPI will infer “body” for these models automatically. You don’t need Body(...) here, and removing it avoids the double-annotation mess.

2) Keep the single-ID DELETE using Query(...) (that’s correct)
from fastapi import Query

@router.delete("/v1/rag/document", response_model=DeleteResponse, dependencies=[Depends(require_rag_write)])
async def delete_document(id: str = Query(..., min_length=1, description="Document ID to delete")) -> DeleteResponse:
    ...

3) Remove any stale/duplicate annotations or imports

If you previously added Annotated[..., Body(...)], remove them as shown above.

Make sure you don’t have something like req: DeleteByIdsRequest = Query(...) anywhere.

Drop unused imports:

If Annotated or Body is not used anymore, remove those imports.

Remove UpsertResponse import from this file (it’s not used).

4) (Only if it still complains) Rebuild forward refs once

At the top of the same file, after importing the delete models, you can add:

from ..models.rag_delete_models import DeleteByIdsRequest, DeleteByNamespaceRequest, DeleteByFilterRequest
DeleteByIdsRequest.model_rebuild()
DeleteByNamespaceRequest.model_rebuild()
DeleteByFilterRequest.model_rebuild()


Most likely unnecessary after step 1–3, but it’s a safe belt-and-suspenders for Pydantic v2.

Quick patch checklist (what likely caused the error)

A previous refactor left Body(...) on the parameter and something (decorator or copy/paste) applied Query(...) to the same param.

Or a helper/decorator that re-wraps the endpoint signature added a Query layer. (Your @log_request_response(...) looks fine if it uses functools.wraps and doesn’t alter the signature—just confirm it doesn’t.)

Validate

Restart and check OpenAPI:

sudo systemctl restart hx-gateway-ml.service && sleep 3
curl -s http://127.0.0.1:4010/openapi.json | jq -r '.paths | keys[]' | sort


Smoke-test delete endpoints:

# by_ids (POST body)
curl -fsS -X POST "http://127.0.0.1:4010/v1/rag/delete/by_ids" \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: $ADMIN_KEY" \
  -d '{"ids":["abc123","def456"]}' | jq .

# by_namespace (POST body)
curl -fsS -X POST "http://127.0.0.1:4010/v1/rag/delete/by_namespace" \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: $ADMIN_KEY" \
  -d '{"namespace":"docs:test"}' | jq .

# by_filter (POST body)
curl -fsS -X POST "http://127.0.0.1:4010/v1/rag/delete/by_filter" \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: $ADMIN_KEY" \
  -d '{"must":[{"key":"namespace","match":{"value":"docs:test"}}]}' | jq .

# single document (DELETE query)
curl -fsS -X DELETE "http://127.0.0.1:4010/v1/rag/document?id=abc123" \
  -H "X-HX-Admin-Key: $ADMIN_KEY" | jq .


Once you drop the accidental Query(...) wrapping of the body models, /openapi.json will stop 500’ing and the service will be healthy.