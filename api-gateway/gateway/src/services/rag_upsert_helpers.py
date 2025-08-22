from __future__ import annotations
import os
import hashlib
from typing import Any, Dict, List, Optional, Sequence, Tuple
import httpx
from fastapi import HTTPException

# ---- Env / Defaults ----
GATEWAY_BASE       = os.environ.get("GATEWAY_BASE", "http://127.0.0.1:4000").rstrip("/")
QDRANT_URL         = os.environ.get("QDRANT_URL", "http://192.168.10.30:6333").rstrip("/")
QDRANT_COLLECTION  = os.environ.get("QDRANT_COLLECTION", "hx_rag_default")
EMBEDDING_MODEL    = os.environ.get("EMBEDDING_MODEL", "emb-premium")
EMBEDDING_FALLBACK = os.environ.get("EMBEDDING_AUTH_HEADER")
LITELLM_PROXY_AUTH = os.environ.get("LITELLM_PROXY_AUTH")

# ---- Helper Functions ----
def hash_id(ns: Optional[str], text: str) -> str:
    base = f"{ns or ''}::{text}".encode("utf-8")
    return hashlib.sha256(base).hexdigest()[:32]

def auth_headers(caller_auth: Optional[str]) -> Dict[str, str]:
    headers = {"Content-Type": "application/json"}
    if caller_auth:
        headers["Authorization"] = caller_auth
    elif EMBEDDING_FALLBACK:
        headers["Authorization"] = EMBEDDING_FALLBACK
    if LITELLM_PROXY_AUTH:
        headers["X-LLM-Proxy-Authorization"] = LITELLM_PROXY_AUTH
    return headers

async def embed_texts(texts: Sequence[str], headers: Dict[str, str]) -> List[List[float]]:
    if ("Authorization" not in headers) and ("X-LLM-Proxy-Authorization" not in headers):
        raise HTTPException(401, "Authorization required to compute embeddings.")
    payload = {"model": EMBEDDING_MODEL, "input": list(texts)}
    async with httpx.AsyncClient(timeout=60.0) as client:
        r = await client.post(f"{GATEWAY_BASE}/v1/embeddings", headers=headers, json=payload)
    if r.status_code != 200:
        raise HTTPException(r.status_code, f"Embeddings error: {r.text}")
    try:
        return [row["embedding"] for row in r.json()["data"]]
    except Exception:
        raise HTTPException(500, "Unexpected embedding response format.")

async def qdrant_upsert(points: List[Dict[str, Any]]) -> Tuple[bool, str]:
    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points"
    async with httpx.AsyncClient(timeout=30.0) as client:
        r = await client.put(url, json={"points": points})
    return r.status_code == 200, r.text
