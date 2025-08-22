# tests/conftest.py
import os, sys, pathlib, pytest
from fastapi.testclient import TestClient

# Make 'gateway' importable when running `pytest` from repo root
REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

# Baseline env for tests (idempotent)
os.environ.setdefault("EMBEDDING_MODEL", "emb-premium")
os.environ.setdefault("EMBEDDING_DIM", "1024")  # guard in helpers
os.environ.setdefault("QDRANT_COLLECTION", "hx_rag_default")
os.environ.setdefault("QDRANT_URL", "http://192.168.10.30:6333")
os.environ.setdefault("GATEWAY_BASE", "http://127.0.0.1:4000")
# Write-scope auth (if you add the dependency)
os.environ.setdefault("RAG_WRITE_KEY", "testsecret")

@pytest.fixture(scope="session")
def app():
    # Import here so env is applied before module import
    from gateway.src.app import build_app
    return build_app()

@pytest.fixture(scope="session")
def client(app):
    return TestClient(app)
