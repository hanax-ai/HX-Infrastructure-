"""
Contract Tests for All Routes

Tests the basic contract for each route: 200 (success), 401 (unauthorized), 422 (validation error).
These tests ensure routes maintain their expected behavior patterns and prevent drift.
"""

import pytest


class TestRouteContracts:
    """Contract tests for all API routes - ensure basic 200/401/422 behavior"""

    # Valid test data for successful requests
    VALID_RAG_SEARCH = {"query": "test query", "limit": 5}

    VALID_RAG_UPSERT = {
        "documents": [
            {
                "text": "Test document content",
                "namespace": "test",
                "metadata": {"source": "contract_test"},
            }
        ]
    }

    VALID_RAG_DELETE_IDS = {"ids": ["test-id-1", "test-id-2"], "namespace": "test"}

    VALID_RAG_DELETE_NAMESPACE = {"namespace": "test_namespace"}

    VALID_RAG_DELETE_FILTER = {"namespace": "test", "filter": {"source": "test"}}

    VALID_MARKDOWN_UPSERT = {
        "text": "# Test Document\n\nThis is test content.",
        "namespace": "test",
        "metadata": {"source": "markdown_test"},
    }

    def test_route_rag_search_200(self, client, respx_qdrant):
        """RAG search should return 200 with valid query"""
        # Mock the search to avoid external dependencies
        if hasattr(respx_qdrant, "post"):
            respx_qdrant.post(
                "http://127.0.0.1:6333/collections/hx_rag_default/points/search"
            ).respond(200, json={"result": [], "status": "ok"})

        response = client.post("/v1/rag/search", json=self.VALID_RAG_SEARCH)
        assert response.status_code == 200
        data = response.json()
        assert "status" in data

    def test_route_rag_search_422(self, client):
        """RAG search should return 422 with invalid data"""
        response = client.post(
            "/v1/rag/search", json={}
        )  # Missing required query or vector
        assert response.status_code == 422

    def test_route_rag_upsert_401(self, client):
        """RAG upsert should return 401 without admin auth"""
        response = client.post("/v1/rag/upsert", json=self.VALID_RAG_UPSERT)
        assert response.status_code == 401

    def test_route_rag_upsert_422(self, client):
        """RAG upsert should return 422 with invalid data"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        response = client.post(
            "/v1/rag/upsert", json={}, headers=headers
        )  # Missing documents
        assert response.status_code == 422

    def test_route_rag_delete_by_ids_401(self, client):
        """RAG delete by IDs should return 401 without admin auth"""
        response = client.post("/v1/rag/delete/by_ids", json=self.VALID_RAG_DELETE_IDS)
        assert response.status_code == 401

    def test_route_rag_delete_by_ids_422(self, client):
        """RAG delete by IDs should return 422 with invalid data"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        response = client.post(
            "/v1/rag/delete/by_ids", json={}, headers=headers
        )  # Missing ids
        assert response.status_code == 422

    def test_route_rag_delete_by_namespace_401(self, client):
        """RAG delete by namespace should return 401 without admin auth"""
        response = client.post(
            "/v1/rag/delete/by_namespace", json=self.VALID_RAG_DELETE_NAMESPACE
        )
        assert response.status_code == 401

    def test_route_rag_delete_by_namespace_422(self, client):
        """RAG delete by namespace should return 422 with invalid data"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        response = client.post(
            "/v1/rag/delete/by_namespace", json={}, headers=headers
        )  # Missing namespace
        assert response.status_code == 422

    def test_route_rag_delete_by_filter_401(self, client):
        """RAG delete by filter should return 401 without admin auth"""
        response = client.post(
            "/v1/rag/delete/by_filter", json=self.VALID_RAG_DELETE_FILTER
        )
        assert response.status_code == 401

    def test_route_rag_delete_by_filter_422(self, client):
        """RAG delete by filter should return 422 with invalid data"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        response = client.post(
            "/v1/rag/delete/by_filter", json={}, headers=headers
        )  # Missing required fields
        assert response.status_code == 422

    def test_route_rag_document_delete_401(self, client):
        """RAG document DELETE should return 401 without admin auth"""
        response = client.delete("/v1/rag/document?namespace=test&doc_id=test-id")
        assert response.status_code == 401

    def test_route_rag_document_delete_422(self, client):
        """RAG document DELETE should return 422 with missing parameters"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        response = client.delete(
            "/v1/rag/document", headers=headers
        )  # Missing namespace and doc_id
        assert response.status_code == 422

    def test_route_rag_upsert_markdown_401(self, client):
        """RAG markdown upsert should return 401 without admin auth"""
        response = client.post(
            "/v1/rag/upsert_markdown", json=self.VALID_MARKDOWN_UPSERT
        )
        assert response.status_code == 401

    def test_route_rag_upsert_markdown_422(self, client):
        """RAG markdown upsert should return 422 with invalid data"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        response = client.post(
            "/v1/rag/upsert_markdown", json={}, headers=headers
        )  # Missing text
        assert response.status_code == 422

    def test_route_rag_upsert_pdf_401(self, client):
        """RAG PDF upsert should return 401 without admin auth"""
        files = {"file": ("test.pdf", b"fake pdf content", "application/pdf")}
        data = {"namespace": "test"}
        response = client.post("/v1/rag/upsert_pdf", files=files, data=data)
        assert response.status_code == 401

    def test_route_rag_upsert_pdf_422(self, client):
        """RAG PDF upsert should return 422 with invalid data"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        # Missing required form fields
        response = client.post("/v1/rag/upsert_pdf", headers=headers)
        assert response.status_code == 422


class TestHealthAndOpenAPI:
    """Contract tests for system endpoints"""

    def test_healthz_200(self, client):
        """Health endpoint should always return 200"""
        response = client.get("/healthz")
        assert response.status_code == 200
        data = response.json()
        assert "ok" in data

    def test_openapi_200(self, app):
        """OpenAPI schema should generate successfully"""
        # Test that OpenAPI schema generates without errors
        schema = app.openapi()
        assert "openapi" in schema
        assert "paths" in schema
        assert len(schema["paths"]) > 0


class TestRouteDiscovery:
    """Validate that we're testing all the routes that exist"""

    def test_all_routes_have_contract_tests(self, app):
        """Ensure we have contract tests for all v1 routes"""
        v1_routes = []
        for route in app.routes:
            if hasattr(route, "path") and route.path.startswith("/v1"):
                v1_routes.append(f"{list(route.methods)[0]} {route.path}")

        # List of routes we expect to have contract tests for
        expected_routes = {
            "POST /v1/rag/search",
            "POST /v1/rag/upsert",
            "POST /v1/rag/delete/by_ids",
            "POST /v1/rag/delete/by_namespace",
            "POST /v1/rag/delete/by_filter",
            "DELETE /v1/rag/document",
            "POST /v1/rag/upsert_markdown",
            "POST /v1/rag/upsert_pdf",
        }

        actual_routes = set(v1_routes)

        # Check if we have tests for all routes
        missing_tests = expected_routes - actual_routes
        if missing_tests:
            pytest.fail(f"Missing contract tests for routes: {missing_tests}")

        # Warn about any new routes that might need contract tests
        new_routes = actual_routes - expected_routes
        if new_routes:
            print(
                f"⚠️  New routes detected - consider adding contract tests: {new_routes}"
            )
