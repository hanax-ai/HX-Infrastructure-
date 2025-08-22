"""
RAG Delete Routes

FastAPI router for RAG document deletion operations with write-scope authentication,
comprehensive error handling, and OpenAPI documentation.
"""

# IMPORTANT: do NOT enable postponed annotations here (breaks OpenAPI with Pydantic v2)

from typing import Dict, Any
from fastapi import APIRouter, Depends, HTTPException, Query, Body

from ..models.rag_delete_models import (
    DeleteByIdsRequest, DeleteByNamespaceRequest, DeleteByFilterRequest, DeleteResponse
)
from ..services import rag_delete_helpers as delsvc
from ..services.security import require_rag_write
from ..utils.structured_logging import log_request_response

# Pydantic defensive rebuilds (no-op if not needed)
try:
    DeleteByIdsRequest.model_rebuild()
    DeleteByNamespaceRequest.model_rebuild()
    DeleteByFilterRequest.model_rebuild()
except Exception:
    pass

router = APIRouter(tags=["rag"])


# Patchable indirection (default delegates to service)
async def qdrant_delete_by_ids(ids):
    return await delsvc.qdrant_delete_by_ids(ids)

async def qdrant_delete_by_filter(qfilter):
    return await delsvc.qdrant_delete_by_filter(qfilter)

async def qdrant_count_points(qfilter=None):
    return await delsvc.qdrant_count_points(qfilter)


@router.post(
    "/v1/rag/delete/by_ids",
    response_model=DeleteResponse,
    dependencies=[Depends(require_rag_write)],
    summary="Delete Documents by IDs",
    description="Precisely delete specific documents by their point IDs",
)
@log_request_response("delete_by_ids")
async def delete_by_ids(req: DeleteByIdsRequest = Body(...)) -> DeleteResponse:
    """Delete specific documents by their point IDs."""
    # Contract: empty list is a no-op with 200 OK
    if not req.ids:
        return DeleteResponse(status="ok", deleted=0, detail=None)

    success, message, count = await qdrant_delete_by_ids(req.ids)

    if not success:
        raise HTTPException(
            status_code=502,
            detail=f"Qdrant delete_by_ids failed: {message[:300]}",
        )

    return DeleteResponse(status="ok", deleted=count)


@router.post(
    "/v1/rag/delete/by_namespace",
    response_model=DeleteResponse,
    dependencies=[Depends(require_rag_write)],
    summary="Delete Documents by Namespace",
    description="Bulk delete all documents within a specific namespace",
)
@log_request_response("delete_by_namespace")
async def delete_by_namespace(req: DeleteByNamespaceRequest = Body(...)) -> DeleteResponse:
    """Bulk delete all documents within a specific namespace."""
    qfilter: Dict[str, Any] = {
        "must": [{"key": "namespace", "match": {"value": req.namespace}}]
    }

    success, message, count = await qdrant_delete_by_filter(qfilter)

    if not success:
        raise HTTPException(
            status_code=502,
            detail=f"Qdrant delete_by_namespace failed: {message[:300]}",
        )

    return DeleteResponse(
        status="ok",
        deleted=count,
        detail="count unknown; use /points/count to verify",
    )


@router.post(
    "/v1/rag/delete/by_filter",
    response_model=DeleteResponse,
    dependencies=[Depends(require_rag_write)],
    summary="Delete Documents by Filter",
    description="Delete documents matching complex filter conditions",
)
@log_request_response("delete_by_filter")
async def delete_by_filter(req: DeleteByFilterRequest = Body(...)) -> DeleteResponse:
    """Delete documents matching complex filter conditions."""
    qfilter: Dict[str, Any] = {}

    if req.must:
        qfilter["must"] = req.must
    if req.should:
        qfilter["should"] = req.should
    if req.must_not:
        qfilter["must_not"] = req.must_not

    if not qfilter:
        # Contract expects 422 for "no conditions provided"
        raise HTTPException(
            status_code=422,
            detail="Provide at least one of: must, should, must_not",
        )

    success, message, count = await qdrant_delete_by_filter(qfilter)

    if not success:
        raise HTTPException(
            status_code=502,
            detail=f"Qdrant delete_by_filter failed: {message[:300]}",
        )

    return DeleteResponse(
        status="ok",
        deleted=count,
        detail="count unknown; use /points/count to verify",
    )


@router.delete(
    "/v1/rag/document",
    response_model=DeleteResponse,
    dependencies=[Depends(require_rag_write)],
    summary="Delete Single Document",
    description="Convenience endpoint for deleting a single document by ID",
)
@log_request_response("delete_document")
async def delete_document(
    id: str = Query(..., min_length=1, description="Document ID to delete")
) -> DeleteResponse:
    """Convenience endpoint for deleting a single document by ID."""
    success, message, count = await qdrant_delete_by_ids([id])

    if not success:
        raise HTTPException(
            status_code=502,
            detail=f"Qdrant delete_document failed: {message[:300]}",
        )

    return DeleteResponse(status="ok", deleted=count)
