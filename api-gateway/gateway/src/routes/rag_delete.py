"""
RAG Delete Routes

FastAPI router for RAG document deletion operations with write-scope authentication,
comprehensive error handling, and OpenAPI documentation.
"""

from typing import Any, Dict
from fastapi import APIRouter, Depends, HTTPException, Query, Body

from ..models.rag_delete_models import (
    DeleteByIdsRequest,
    DeleteByNamespaceRequest,
    DeleteByFilterRequest,
    DeleteResponse,
)
from ..services.rag_delete_helpers import qdrant_delete_by_ids, qdrant_delete_by_filter
from ..services.security import require_rag_write
from ..utils.structured_logging import log_request_response

router = APIRouter(tags=["rag"])


@router.post(
    "/v1/rag/delete/by_ids",
    response_model=DeleteResponse,
    dependencies=[Depends(require_rag_write)],
    summary="Delete Documents by IDs",
    description="Precisely delete specific documents by their point IDs",
    responses={
        200: {
            "description": "Documents successfully deleted",
            "content": {
                "application/json": {
                    "example": {"status": "ok", "deleted": 3, "detail": None}
                }
            },
        },
        401: {"description": "Authentication required"},
        403: {"description": "Invalid admin key - write access required"},
        422: {"description": "Validation error - invalid request format"},
        502: {"description": "Qdrant vector database error"},
    },
)
async def delete_by_ids(req: DeleteByIdsRequest = Body(...)) -> DeleteResponse:
    """Delete specific documents by their point IDs."""
    success, message, count = await qdrant_delete_by_ids(req.ids)

    if not success:
        raise HTTPException(
            status_code=502, detail=f"Qdrant delete_by_ids failed: {message[:300]}"
        )

    return DeleteResponse(status="ok", deleted=count)


@router.post(
    "/v1/rag/delete/by_namespace",
    response_model=DeleteResponse,
    dependencies=[Depends(require_rag_write)],
    summary="Delete Documents by Namespace",
    description="Bulk delete all documents within a specific namespace",
    responses={
        200: {
            "description": "Namespace successfully cleared",
            "content": {
                "application/json": {
                    "example": {
                        "status": "ok",
                        "deleted": -1,
                        "detail": "count unknown; use /points/count to verify",
                    }
                }
            },
        },
        401: {"description": "Authentication required"},
        403: {"description": "Invalid admin key - write access required"},
        422: {"description": "Validation error - invalid namespace format"},
        502: {"description": "Qdrant vector database error"},
    },
)
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
        status="ok", deleted=count, detail="count unknown; use /points/count to verify"
    )


@router.post(
    "/v1/rag/delete/by_filter",
    response_model=DeleteResponse,
    dependencies=[Depends(require_rag_write)],
    summary="Delete Documents by Filter",
    description="Delete documents matching complex filter conditions",
    responses={
        200: {
            "description": "Filtered documents successfully deleted",
            "content": {
                "application/json": {
                    "example": {
                        "status": "ok",
                        "deleted": -1,
                        "detail": "count unknown; use /points/count to verify",
                    }
                }
            },
        },
        400: {"description": "Invalid filter - provide at least one condition"},
        401: {"description": "Authentication required"},
        403: {"description": "Invalid admin key - write access required"},
        422: {"description": "Validation error - invalid filter format"},
        502: {"description": "Qdrant vector database error"},
    },
)
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
        raise HTTPException(
            status_code=400, detail="Provide at least one of: must, should, must_not"
        )

    success, message, count = await qdrant_delete_by_filter(qfilter)

    if not success:
        raise HTTPException(
            status_code=502,
            detail=f"Qdrant delete_by_filter failed: {message[:300]}",
        )

    return DeleteResponse(
        status="ok", deleted=count, detail="count unknown; use /points/count to verify"
    )


@router.delete(
    "/v1/rag/document",
    response_model=DeleteResponse,
    dependencies=[Depends(require_rag_write)],
    summary="Delete Single Document",
    description="Convenience endpoint for deleting a single document by ID",
    responses={
        200: {
            "description": "Document successfully deleted",
            "content": {
                "application/json": {
                    "example": {"status": "ok", "deleted": 1, "detail": None}
                }
            },
        },
        401: {"description": "Authentication required"},
        403: {"description": "Invalid admin key - write access required"},
        422: {"description": "Validation error - ID required"},
        502: {"description": "Qdrant vector database error"},
    },
)
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
