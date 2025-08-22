# tests/test_route_upsert.py
import os

# We'll patch at the route module import site
import gateway.src.routes.rag_upsert as route
import pytest


@pytest.fixture(autouse=True)
def _prep_env(monkeypatch):
    monkeypatch.setenv("EMBEDDING_DIM", "1024")
    monkeypatch.setenv("RAG_WRITE_KEY", "test-admin-key")  # if you enforce write-scope
    monkeypatch.setenv("HX_ADMIN_KEY", "test-admin-key")  # security layer expects this
    monkeypatch.setenv(
        "EMBEDDING_AUTH_HEADER", "Bearer test-embedding-key"
    )  # for embedding calls
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
        # Use the real validation function
        from gateway.src.services.rag_upsert_helpers import _validate_point_vectors

        _validate_point_vectors(
            points
        )  # This will raise HTTPException(400) if dimensions wrong
        return True, "ok"

    monkeypatch.setattr(route, "qdrant_upsert", bad_dim_qdrant, raising=True)


def test_upsert_happy_path(client, patch_embed_and_upsert):
    payload = {
        "documents": [
            {
                "text": "Citadel is HX's AI OS.",
                "namespace": "docs:test",
                "metadata": {"source": "inline"},
            },
            {
                "text": "RAG is retrieval augmented generation.",
                "namespace": "docs:test",
            },
        ],
        "batch_size": 64,
    }
    # If you enforce write key dependency, include header:
    headers = {"X-HX-Admin-Key": os.getenv("RAG_WRITE_KEY", "")}
    r = client.post("/v1/rag/upsert", json=payload, headers=headers)
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["status"] == "ok"
    assert data["upserted"] == 2
    assert data["failed"] == 0


def test_upsert_rejects_bad_vector_length(client):
    # No patching - let the real helper validation work
    payload = {
        "documents": [
            {
                "vector": [0.1, 0.2, 0.3],
                "namespace": "docs:test",
                "metadata": {"source": "inline"},
            }
        ]
    }
    headers = {"X-HX-Admin-Key": os.getenv("RAG_WRITE_KEY", "")}
    r = client.post("/v1/rag/upsert", json=payload, headers=headers)
    assert r.status_code == 400
    assert ("1024 dims" in r.text and "got 3" in r.text) or "length mismatch" in r.text


def test_upsert_requires_text_or_vector(client):
    payload = {"documents": [{"namespace": "docs:test", "metadata": {"k": "v"}}]}
    headers = {"X-HX-Admin-Key": os.getenv("RAG_WRITE_KEY", "")}
    r = client.post("/v1/rag/upsert", json=payload, headers=headers)
    # No text/vector → model validation rejects with 422 (proper separation of concerns)
    assert r.status_code == 422
    assert "Document must provide either" in r.text and (
        "text" in r.text and "vector" in r.text
    )
