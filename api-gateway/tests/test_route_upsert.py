# tests/test_route_upsert.py
import os, json, pytest
from fastapi import HTTPException

# We'll patch at the route module import site
import gateway.src.routes.rag_upsert as route

@pytest.fixture(autouse=True)
def _prep_env(monkeypatch):
    monkeypatch.setenv("EMBEDDING_DIM", "1024")
    monkeypatch.setenv("RAG_WRITE_KEY", "testsecret")  # if you enforce write-scope
    yield

def _vec(n=1024):
    return [0.0] * n

@pytest.fixture
def patch_embed_and_upsert(monkeypatch):
    async def fake_embed_texts(texts, headers):
        # Return one vector per text
        return [_vec() for _ in texts]

    async def fake_qdrant_upsert(points):
        # Validate shape minimally, pretend success
        assert all("id" in p and "vector" in p for p in points)
        return True, "ok"

    monkeypatch.setattr(route, "embed_texts", fake_embed_texts, raising=True)
    monkeypatch.setattr(route, "qdrant_upsert", fake_qdrant_upsert, raising=True)

@pytest.fixture
def patch_qdrant_bad_dim(monkeypatch):
    async def bad_dim_qdrant(points):
        # Simulate server-side guard
        for p in points:
            if len(p.get("vector", [])) != 1024:
                raise HTTPException(400, "Vector length mismatch")
        return True, "ok"
    monkeypatch.setattr(route, "qdrant_upsert", bad_dim_qdrant, raising=True)

def test_upsert_happy_path(client, patch_embed_and_upsert):
    payload = {
        "documents": [
            {"text": "Citadel is HX's AI OS.", "namespace": "docs:test", "metadata": {"source":"inline"}},
            {"text": "RAG is retrieval augmented generation.", "namespace": "docs:test"}
        ],
        "batch_size": 64
    }
    # If you enforce write key dependency, include header:
    headers = {"X-HX-Admin-Key": os.getenv("RAG_WRITE_KEY", "")}
    r = client.post("/v1/rag/upsert", json=payload, headers=headers)
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["status"] == "ok"
    assert data["upserted"] == 2
    assert data["failed"] == 0

def test_upsert_rejects_bad_vector_length(client, patch_qdrant_bad_dim):
    payload = {
        "documents": [
            {"vector": [0.1, 0.2, 0.3], "namespace": "docs:test", "metadata":{"source":"inline"}}
        ]
    }
    headers = {"X-HX-Admin-Key": os.getenv("RAG_WRITE_KEY", "")}
    r = client.post("/v1/rag/upsert", json=payload, headers=headers)
    assert r.status_code == 400
    assert "Vector length" in r.text or "length mismatch" in r.text

def test_upsert_requires_text_or_vector(client):
    payload = {"documents":[{"namespace":"docs:test","metadata":{"k":"v"}}]}
    headers = {"X-HX-Admin-Key": os.getenv("RAG_WRITE_KEY", "")}
    r = client.post("/v1/rag/upsert", json=payload, headers=headers)
    # No text/vector → route counts it as failed and returns 200 with failed=1
    assert r.status_code == 200
    data = r.json()
    assert data["failed"] >= 1
