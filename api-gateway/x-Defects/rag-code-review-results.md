Here’s a focused review and a drop-in refinement that keeps behavior the same but tightens correctness, consistency (with your services layer), and Pydantic v2 hygiene.

What to fix (concise)

Remove unused imports: UploadFile, File, Form, and UpsertResponse aren’t used here.

Pydantic v2 hygiene: Forbid extra fields on the request model to prevent schema drift.

Consistent auth passthrough: Add support for X-LLM-Proxy-Authorization like your services layer.

Optional dim guard: If EMBEDDING_DIM is set, validate vector length up front (prevents Qdrant 400s).

Small niceties: Keep timeouts, keep rstrip on bases, and return raw Qdrant payload as you do now.

Drop-in replacement (gateway/src/routes/rag.py)
from __future__ import annotations

import os
from typing import Any, Dict, List, Optional

import httpx
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field, ConfigDict, conlist

router = APIRouter(tags=["rag"])

# ---- Environment / Defaults -------------------------------------------------
GATEWAY_BASE = os.environ.get("GATEWAY_BASE", "http://127.0.0.1:4000").rstrip("/")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://192.168.10.30:6333").rstrip("/")
QDRANT_COLLECTION = os.environ.get("QDRANT_COLLECTION", "hx_rag_default")
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "emb-premium")
EMBEDDING_AUTH_HEADER = os.environ.get("EMBEDDING_AUTH_HEADER")  # Bearer sk-...
LITELLM_PROXY_AUTH = os.environ.get("LITELLM_PROXY_AUTH")        # optional proxy auth passthrough
EMBEDDING_DIM = int(os.environ.get("EMBEDDING_DIM", "0"))        # optional hard guard (0 = disabled)

# ---- Request / Response Models ---------------------------------------------

class RagSearchRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    # Either provide 'query' (we'll embed), or a precomputed 'vector'
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

def _auth_headers(auth_header: Optional[str]) -> Dict[str, str]:
    """
    Build headers for the embeddings call:
    - Prefer caller Authorization
    - Else fall back to EMBEDDING_AUTH_HEADER
    - Optionally pass X-LLM-Proxy-Authorization if set
    """
    if not (auth_header or EMBEDDING_AUTH_HEADER):
        raise HTTPException(401, "Authorization required to compute embeddings.")
    headers = {"Content-Type": "application/json"}
    headers["Authorization"] = auth_header or EMBEDDING_AUTH_HEADER  # type: ignore
    if LITELLM_PROXY_AUTH:
        headers["X-LLM-Proxy-Authorization"] = LITELLM_PROXY_AUTH
    return headers

async def _compute_embedding(text: str, headers: Dict[str, str]) -> List[float]:
    payload = {"model": EMBEDDING_MODEL, "input": text}
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
        headers = _auth_headers(request.headers.get("authorization"))
        vector = await _compute_embedding(req.query, headers)
    else:
        # Optional strict dimension check (if EMBEDDING_DIM set)
        if EMBEDDING_DIM > 0 and len(vector) != EMBEDDING_DIM:
            raise HTTPException(
                400,
                f"Embedding vector must be {EMBEDDING_DIM} dimensions; got {len(vector)}.",
            )

    # 2) Search in Qdrant
    result = await _qdrant_search(
        vector=vector,
        limit=req.limit,
        threshold=req.score_threshold,
        namespace=req.namespace,
    )
    return RagSearchResponse(status="ok", result=result)

Why these changes

Consistency with services layer: _auth_headers mirrors how you already handle X-LLM-Proxy-Authorization in helpers.

Safer input: extra="forbid" avoids silent acceptance of unexpected fields.

Operational guardrail: EMBEDDING_DIM (if set) prevents mismatched vectors from reaching Qdrant.

Clean imports: Avoids bringing in upload-related symbols that triggered UploadFile Pydantic field errors elsewhere.

Same behavior: You still return raw Qdrant payload under result, preserving clients’ expectations.

Quick validation commands
# OpenAPI contains the route
curl -fsS http://127.0.0.1:4010/openapi.json | jq -r '.paths | keys[]' | grep /v1/rag/search

# Vector path (will 400 if EMBEDDING_DIM mismatch and is set)
python3 - <<'PY' >/tmp/vec.json
import json; print(json.dumps({"vector":[0.0]*1024,"limit":3}))
PY
curl -fsS -X POST http://127.0.0.1:4010/v1/rag/search -H 'Content-Type: application/json' -d @/tmp/vec.json | jq .

# Query path (requires caller auth or fallback env)
curl -fsS -X POST http://127.0.0.1:4010/v1/rag/search \
  -H "Authorization: Bearer $USER_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"query":"hello","limit":1,"namespace":"docs:test"}' | jq .


If you want to go fully SOLID later, we can pull _compute_embedding and _qdrant_search into services/rag_search_service.py and keep this route as a thin controller, but the above is a safe, minimal improvement that unblocks you now.