# tests/conftest.py
"""
Test Configuration & Environment Setup

Sets up controlled environment variables for deterministic test execution.
All tests inherit these baseline settings, ensuring consistent behavior
across different machines and CI/CD environments.

Environment Controls:
- STRICT_DB=0: Allow pipeline without database connection
- Controlled service URLs: Use localhost test instances
- Deterministic auth keys: Predictable test credentials
- Fixed dimensions: Consistent validation behavior

Mocking Strategy:
- Individual tests use monkeypatch for service mocking
- Optional respx fixtures available for HTTP mocking
- Environment isolation prevents production value leakage
"""

import os
import pathlib
import sys

import pytest
from fastapi.testclient import TestClient

# Make 'gateway' importable when running `pytest` from repo root
REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

# Controlled environment for deterministic tests
os.environ.setdefault("STRICT_DB", "0")  # allow pipeline without DB
os.environ.setdefault("EMBEDDING_DIM", "1024")  # dimension validation guard
os.environ.setdefault("QDRANT_URL", "http://127.0.0.1:6333")  # local test instance
os.environ.setdefault("QDRANT_COLLECTION", "hx_rag_default")
os.environ.setdefault("ADMIN_KEY", "sk-test-admin")  # admin authentication
os.environ.setdefault("EMBEDDING_MODEL", "emb-premium")
os.environ.setdefault("GATEWAY_BASE", "http://127.0.0.1:4000")
# Additional auth keys for compatibility
os.environ.setdefault("RAG_WRITE_KEY", "test-admin-key")
os.environ.setdefault("HX_ADMIN_KEY", "test-admin-key")  # security layer expects this
os.environ.setdefault(
    "EMBEDDING_AUTH_HEADER", "Bearer test-embedding-key"
)  # for embedding calls


@pytest.fixture(scope="session")
def app():
    # Import here so env is applied before module import
    from gateway.src.app import build_app

    return build_app()


@pytest.fixture(scope="session")
def client(app):
    return TestClient(app)


# Example fixtures for optional HTTP mocking (respx)
# Note: Individual tests already use monkeypatch for service mocking
# These are available if you prefer respx over monkeypatch for HTTP calls
# To use: pip install respx, then uncomment the import and fixture contents


@pytest.fixture
def respx_qdrant():
    """Optional: respx mock for Qdrant endpoints (alternative to monkeypatch)"""
    # import respx
    # with respx.mock:
    #     yield respx
    pytest.skip("respx not configured - use monkeypatch mocking instead")


@pytest.fixture
def respx_embedding():
    """Optional: respx mock for embedding service (alternative to monkeypatch)"""
    # import respx
    # with respx.mock:
    #     yield respx
    pytest.skip("respx not configured - use monkeypatch mocking instead")
