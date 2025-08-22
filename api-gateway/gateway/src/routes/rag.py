# /opt/HX-Infrastructure-/api-gateway/gateway/src/routes/rag.py
from __future__ import annotations

import os
from typing import Any, Dict, List, Optional

import httpx
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field, conlist

router = APIRouter(tags=["rag"])

# ---- Environment / Defaults -------------------------------------------------
GATEWAY_BASE = os.environ.get("GATEWAY_BASE", "http://127.0.0.1:4000").rstrip("/")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://192.168.10.30:6333").rstrip("/")
QDRANT_COLLECTION = os.environ.get("QDRANT_COLLECTION", "hx_rag_default")
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "emb-premium")
EMBEDDING_AUTH_HEADER = os.environ.get("EMBEDDING_AUTH_HEADER")

# ---- Request / Response Models ---------------------------------------------

class RagSearchRequest(BaseModel):
    query: Optional[str] = Field(default=None, description="Free text to embed")
    vector: Optional[conlist(float, min_length=8)] = Field(
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
    result: Dict[str, Any]

# ---- Helpers ---------------------------------------------------------------

async def _compute_embedding(text: str, auth_header: Optional[str]) -> List[float]:
    if not auth_header:
        raise HTTPException(401, "Authorization required to compute embeddings.")
    payload = {"model": EMBEDDING_MODEL, "input": text}
    headers = {"Authorization": auth_header, "Content-Type": "application/json"}
    async with httpx.AsyncClient(timeout=20.0) as client:
        r = await client.post(f"{GATEWAY_BASE}/v1/embeddings", headers=headers, json=payload)
    if r.status_code != 200:
        raise HTTPException(r.status_code, f"Embeddings error: {r.text}")
    try:
        data = r.json()
        return data["data"][0]["embedding"]
    except Exception:
        raise HTTPException(500, "Unexpected embedding response format.")

async def _qdrant_search(
    vector: List[float],
    limit: int,
    threshold: Optional[float],
    namespace: Optional[str],
) -> Dict[str, Any]:
    body: Dict[str, Any] = {
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
    async with httpx.AsyncClient(timeout=15.0) as client:
        r = await client.post(url, json=body)
    if r.status_code != 200:
        raise HTTPException(r.status_code, f"Qdrant error: {r.text}")
    return r.json()

# ---- Route -----------------------------------------------------------------

@router.post("/v1/rag/search", response_model=RagSearchResponse)
async def rag_search(req: RagSearchRequest, request: Request) -> RagSearchResponse:
    # 1) Determine vector
    vector = req.vector
    if vector is None:
        if not req.query:
            raise HTTPException(400, "Provide either 'vector' or 'query'.")
        caller_auth = request.headers.get("authorization")
        auth = caller_auth or EMBEDDING_AUTH_HEADER
        vector = await _compute_embedding(req.query, auth)

    # 2) Qdrant search
    result = await _qdrant_search(
        vector=vector,
        limit=req.limit,
        threshold=req.score_threshold,
        namespace=req.namespace,
    )
    return RagSearchResponse(status="ok", result=result)
