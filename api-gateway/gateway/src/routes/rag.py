# /opt/HX-Infrastructure-/api-gateway/gateway/src/routes/rag.py

import os
import logging
from typing import Annotated, Any, Optional

import httpx
from fastapi import APIRouter, Body, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from ..services import security as security_helpers
from ..services.security import get_embedding_auth_from_request

router = APIRouter(tags=["rag"])
logger = logging.getLogger(__name__)

# ---- Environment / Defaults -------------------------------------------------
GATEWAY_BASE = os.environ.get("GATEWAY_BASE", "http://127.0.0.1:4000").rstrip("/")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://192.168.10.30:6333").rstrip("/")
QDRANT_COLLECTION = os.environ.get("QDRANT_COLLECTION", "hx_rag_default")
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "emb-premium")

# ---- Request / Response Models ---------------------------------------------


class RagSearchRequest(BaseModel):
    query: Optional[str] = Field(default=None, description="Free text to embed")
    vector: Optional[list[float]] = Field(
        default=None, description="Precomputed embedding vector"
    )
    limit: int = Field(default=5, ge=1, le=100)
    score_threshold: Optional[float] = Field(
        default=None, description="Optional min similarity score (Qdrant)"
    )
    namespace: Optional[str] = Field(
        default=None, description="Optional namespace filter (payload.namespace)"
    )


class RagSearchResponse(BaseModel):
    status: str
    result: dict[str, Any]


# ---- Helpers ---------------------------------------------------------------


async def _compute_embedding(
    text: str, auth_header: str | None
) -> list[float]:
    if not auth_header:
        raise HTTPException(401, "Authorization required for embedding computation")
    
    payload = {"model": EMBEDDING_MODEL, "input": text}
    headers = {"Authorization": auth_header, "Content-Type": "application/json"}
    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            r = await client.post(
                f"{GATEWAY_BASE}/v1/embeddings", headers=headers, json=payload
            )
    except httpx.RequestError as e:
        raise HTTPException(502, f"Could not connect to embedding service: {e}")
    if r.status_code != 200:
        raise HTTPException(r.status_code, f"Embeddings error: {r.text}")
    try:
        data = r.json()
        return data["data"][0]["embedding"]
    except Exception:
        raise HTTPException(500, "Unexpected embedding response format.")


async def _qdrant_search(
    vector: list[float],
    limit: int,
    threshold: Optional[float],
    namespace: Optional[str],
) -> dict[str, Any]:
    body: dict[str, Any] = {
        "vector": vector,
        "limit": limit,
        "with_payload": True,
        "with_vectors": False,
    }
    if threshold is not None and threshold > 0:
        body["score_threshold"] = threshold
    if namespace:
        body["filter"] = {"must": [{"key": "namespace", "match": {"value": namespace}}]}

    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points/search"
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            r = await client.post(url, json=body)
    except httpx.RequestError as e:
        raise HTTPException(503, f"Could not connect to Qdrant: {e}")
    if r.status_code != 200:
        raise HTTPException(r.status_code, f"Qdrant error: {r.text}")
    return r.json()


async def _search_qdrant(vector: list[float], limit: int) -> dict[str, Any]:
    """Simplified search wrapper for basic RAG search."""
    return await _qdrant_search(
        vector=vector,
        limit=limit,
        threshold=None,
        namespace=None
    )


# ---- Route -----------------------------------------------------------------


@router.post("/v1/rag/search", summary="Search RAG documents")
async def search_rag(
    auth: Annotated[str, Depends(security_helpers.get_embedding_auth)],
    query: str = Body(..., description="Search query text"),
    limit: int = Body(5, description="Number of results to return", ge=1, le=100)
):
    if not query or not query.strip():
        raise HTTPException(
            status_code=422, 
            detail={"error": "Query cannot be empty", "type": "validation_error"}
        )
    
    try:
        search_vector = await _compute_embedding(query, auth)
    except HTTPException:
        raise  # Re-raise embedding computation errors as-is
    
    try:
        response = await _search_qdrant(search_vector, limit)
        return response
    except Exception as e:
        logger.error(f"RAG search failed: {e}")
        raise HTTPException(500, f"Search failed: {e}")
