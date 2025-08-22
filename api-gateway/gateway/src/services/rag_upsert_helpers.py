from __future__ import annotations

import hashlib
import os
from collections.abc import Sequence
from typing import Any

import httpx
from fastapi import HTTPException

# ---- Env / Defaults ----
GATEWAY_BASE = os.environ.get("GATEWAY_BASE", "http://127.0.0.1:4000").rstrip("/")
QDRANT_URL = os.environ.get("QDRANT_URL", "http://192.168.10.30:6333").rstrip("/")
QDRANT_COLLECTION = os.environ.get("QDRANT_COLLECTION", "hx_rag_default")
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "emb-premium")
EMBEDDING_DIM = int(os.environ.get("EMBEDDING_DIM", "1024"))
LITELLM_PROXY_AUTH = os.environ.get("LITELLM_PROXY_AUTH")


# ---- Helper Functions ----
def hash_id(ns: str | None, text: str) -> str:
    base = f"{ns or ''}::{text}".encode()
    return hashlib.sha256(base).hexdigest()[:32]


def auth_headers(caller_auth: str) -> dict[str, str]:
    """
    Build headers for embedding service calls.

    Args:
        caller_auth: Resolved authorization header value (should never be None)

    Returns:
        Headers dict with Authorization and optional proxy auth
    """
    headers = {"Content-Type": "application/json", "Authorization": caller_auth}
    if LITELLM_PROXY_AUTH:
        headers["X-LLM-Proxy-Authorization"] = LITELLM_PROXY_AUTH
    return headers


async def embed_texts(
    texts: Sequence[str], headers: dict[str, str]
) -> list[list[float]]:
    if ("Authorization" not in headers) and (
        "X-LLM-Proxy-Authorization" not in headers
    ):
        raise HTTPException(401, "Authorization required to compute embeddings.")
    payload = {"model": EMBEDDING_MODEL, "input": list(texts)}
    async with httpx.AsyncClient(timeout=60.0) as client:
        r = await client.post(
            f"{GATEWAY_BASE}/v1/embeddings", headers=headers, json=payload
        )
    if r.status_code != 200:
        raise HTTPException(r.status_code, f"Embeddings error: {r.text}")
    try:
        return [row["embedding"] for row in r.json()["data"]]
    except Exception:
        raise HTTPException(500, "Unexpected embedding response format.")


def _validate_point_vectors(points: list[dict[str, Any]]) -> None:
    """Raise HTTPException(400) if any vector length != EMBEDDING_DIM."""
    if EMBEDDING_DIM <= 0:
        return
    for i, p in enumerate(points):
        v = p.get("vector")
        if v is None:
            raise HTTPException(400, f"Point {i} missing 'vector'")
        if len(v) != EMBEDDING_DIM:
            raise HTTPException(
                400, f"Vector at {i} must be {EMBEDDING_DIM} dims, got {len(v)}"
            )


async def qdrant_upsert(points: list[dict[str, Any]]) -> tuple[bool, str]:
    _validate_point_vectors(points)
    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points?wait=true"
    async with httpx.AsyncClient(timeout=30.0) as client:
        r = await client.put(url, json={"points": points})
    return r.status_code == 200, r.text
