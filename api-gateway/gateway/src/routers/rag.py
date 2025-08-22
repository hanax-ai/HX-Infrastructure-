from __future__ import annotations
from typing import Any, Dict, List, Optional
import os
import httpx
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

router = APIRouter()

GATEWAY_BASE       = os.environ.get("GATEWAY_BASE", "http://127.0.0.1:4000")
QDRANT_URL         = os.environ.get("QDRANT_URL", "http://192.168.10.30:6333").rstrip("/")
QDRANT_COLLECTION  = os.environ.get("QDRANT_COLLECTION", "hx_rag_default")
EMBEDDING_MODEL    = os.environ.get("EMBEDDING_MODEL", "emb-premium")
EMBEDDING_FALLBACK = os.environ.get("EMBEDDING_AUTH_HEADER", None)  # e.g., "Bearer sk-xxxx"

class RagSearchRequest(BaseModel):
    query: Optional[str] = None
    vector: Optional[List[float]] = None
    limit: int = 5
    score_threshold: Optional[float] = None
    namespace: Optional[str] = None

@router.post("/v1/rag/search")
async def rag_search(req: RagSearchRequest, request: Request):
    # 1) Get or compute a vector
    vector = req.vector
    if vector is None:
        if not req.query:
            raise HTTPException(400, "Provide either 'vector' or 'query'.")
        # Prefer caller's Authorization; else fallback env
        auth = request.headers.get("authorization") or EMBEDDING_FALLBACK
        if not auth:
            raise HTTPException(401, "Authorization required to compute embeddings.")
        payload = {"model": EMBEDDING_MODEL, "input": req.query}
        headers = {"Authorization": auth, "Content-Type": "application/json"}
        async with httpx.AsyncClient(timeout=20.0) as client:
            r = await client.post(f"{GATEWAY_BASE}/v1/embeddings", headers=headers, json=payload)
            if r.status_code != 200:
                raise HTTPException(r.status_code, f"Embeddings error: {r.text}")
            data = r.json()
            try:
                vector = data["data"][0]["embedding"]
            except Exception:
                raise HTTPException(500, "Unexpected embedding response format")

    # 2) Qdrant search
    body: Dict[str, Any] = {
        "vector": vector,
        "limit": req.limit,
        "with_payload": True,
        "with_vectors": False,
    }
    if req.score_threshold is not None and req.score_threshold > 0:
        body["score_threshold"] = req.score_threshold
    if req.namespace:
        body["filter"] = {"must": [{"key": "namespace", "match": {"value": req.namespace}}]}

    async with httpx.AsyncClient(timeout=15.0) as client:
        url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points/search"
        resp = await client.post(url, json=body)
        if resp.status_code != 200:
            raise HTTPException(resp.status_code, f"Qdrant error: {resp.text}")
        return {"status": "ok", "result": resp.json()}
