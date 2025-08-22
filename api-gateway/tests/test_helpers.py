# tests/test_helpers.py
import os
import pytest
from fastapi import HTTPException
from gateway.src.services import rag_upsert_helpers as H

def test_hash_id_is_deterministic_and_namespace_sensitive():
    a = H.hash_id("ns", "text")
    b = H.hash_id("ns", "text")
    c = H.hash_id("ns2", "text")
    d = H.hash_id("ns", "text2")
    assert a == b
    assert a != c
    assert a != d
    assert len(a) == 32  # truncated sha256 hex

def test_auth_headers_precedence(monkeypatch):
    monkeypatch.delenv("EMBEDDING_AUTH_HEADER", raising=False)
    monkeypatch.delenv("LITELLM_PROXY_AUTH", raising=False)
    # no env, only caller auth
    h = H.auth_headers("Bearer USER")
    assert h.get("Authorization") == "Bearer USER"
    assert "X-LLM-Proxy-Authorization" not in h

    # with fallback + proxy env
    monkeypatch.setenv("EMBEDDING_AUTH_HEADER", "Bearer FALLBACK")
    monkeypatch.setenv("LITELLM_PROXY_AUTH", "Bearer PROXY")
    # rebuild module-level env vars
    import importlib; importlib.reload(H)
    h = H.auth_headers(None)
    assert h.get("Authorization") == "Bearer FALLBACK"
    assert h.get("X-LLM-Proxy-Authorization") == "Bearer PROXY"

@pytest.mark.asyncio
async def test_qdrant_upsert_dimension_guard(monkeypatch):
    # Ensure guard is active
    monkeypatch.setenv("EMBEDDING_DIM", "1024")
    import importlib; importlib.reload(H)

    # Build a bad vector length
    points = [{"id": "p1", "vector": [0.0, 0.1, 0.2], "payload": {}}]
    with pytest.raises(HTTPException) as ei:
        await H.qdrant_upsert(points)
    assert ei.value.status_code == 400
    assert "Vector length" in str(ei.value.detail)
