# tests/test_route_delete.py
"""
Test suite for RAG delete operations including:
- Delete by IDs
- Delete by namespace
- Delete by filter
- Single document delete
- Authentication and authorization
"""

# Import the route modules we're testing
import gateway.src.routes.rag_delete as delete_route
import pytest
import pytest


@pytest.fixture(autouse=True)
def _prep_env(monkeypatch):
    """Set up test environment variables"""
    monkeypatch.setenv("RAG_WRITE_KEY", "test-admin-key")
    monkeypatch.setenv("HX_ADMIN_KEY", "test-admin-key")
    monkeypatch.setenv("QDRANT_URL", "http://test-qdrant:6333")
    monkeypatch.setenv("QDRANT_COLLECTION", "test_collection")
    yield


@pytest.fixture
def mock_successful_delete(monkeypatch):
    """Mock successful Qdrant delete operations with verification"""

    async def fake_delete_by_ids(point_ids):
        # New behavior: return verified count (simulating successful verification)
        return True, f"Deleted {len(point_ids)} points", len(point_ids)

    async def fake_delete_by_filter(filter_conditions):
        # New behavior: return verified count for filter operations too
        # Simulate finding 3 matching documents for consistency with expectations
        return True, "Deleted points matching filter", 3

    async def fake_count_points(filter_conditions=None):
        # Mock count function to support verification
        return True, 3  # Simulate 3 points found

    # Patch at the route module level where our resolver will find them
    monkeypatch.setattr(delete_route, "qdrant_delete_by_ids", fake_delete_by_ids)
    monkeypatch.setattr(delete_route, "qdrant_delete_by_filter", fake_delete_by_filter)
    monkeypatch.setattr(delete_route, "qdrant_count_points", fake_count_points)


@pytest.fixture
def mock_qdrant_error(monkeypatch):
    """Mock Qdrant errors for error handling tests"""

    async def failing_delete(*args, **kwargs):
        return False, "Qdrant connection failed", 0

    # Patch at the route module level where our resolver will find them
    monkeypatch.setattr(delete_route, "qdrant_delete_by_ids", failing_delete)
    monkeypatch.setattr(delete_route, "qdrant_delete_by_filter", failing_delete)


class TestDeleteByIds:
    """Test delete by IDs functionality"""

    def test_delete_by_ids_success(self, client, mock_successful_delete):
        """Test successful deletion by IDs"""
        payload = {
            "ids": [
                "e1b7f1e9-8593-b454-38b9-05fd426e8984",
                "4ae44d41-7604-dd89-b285-bf43a70fda9a",
            ]
        }
        headers = {"X-HX-Admin-Key": "test-admin-key"}

        response = client.post("/v1/rag/delete/by_ids", json=payload, headers=headers)

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["deleted"] == 2
        assert data["detail"] is None

    def test_delete_by_ids_requires_auth(self, client):
        """Test that delete by IDs requires admin authentication"""
        payload = {"ids": ["test-id-1"]}

        # No auth header
        response = client.post("/v1/rag/delete/by_ids", json=payload)
        assert response.status_code == 401

        # Wrong auth key
        headers = {"X-HX-Admin-Key": "wrong-key"}
        response = client.post("/v1/rag/delete/by_ids", json=payload, headers=headers)
        assert response.status_code == 401

    def test_delete_by_ids_empty_list(self, client, mock_successful_delete):
        """Test deletion with empty ID list"""
        payload = {"ids": []}
        headers = {"X-HX-Admin-Key": "test-admin-key"}

        response = client.post("/v1/rag/delete/by_ids", json=payload, headers=headers)

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["deleted"] == 0

    def test_delete_by_ids_invalid_request(self, client):
        """Test deletion with invalid request format"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}

        # Missing ids field
        response = client.post("/v1/rag/delete/by_ids", json={}, headers=headers)
        assert response.status_code == 422

        # Invalid ids type
        response = client.post(
            "/v1/rag/delete/by_ids", json={"ids": "not-a-list"}, headers=headers
        )
        assert response.status_code == 422

    def test_delete_by_ids_qdrant_error(self, client, mock_qdrant_error):
        """Test handling of Qdrant errors"""
        payload = {"ids": ["test-id"]}
        headers = {"X-HX-Admin-Key": "test-admin-key"}

        response = client.post("/v1/rag/delete/by_ids", json=payload, headers=headers)

        assert response.status_code == 502
        assert "Qdrant connection failed" in response.text


class TestDeleteByNamespace:
    """Test delete by namespace functionality"""

    def test_delete_by_namespace_success(self, client, mock_successful_delete):
        """Test successful deletion by namespace"""
        payload = {"namespace": "docs:test"}
        headers = {"X-HX-Admin-Key": "test-admin-key"}

        response = client.post(
            "/v1/rag/delete/by_namespace", json=payload, headers=headers
        )

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["deleted"] == 3  # Count verified through before/after comparison
        assert "verified" in data["detail"]

    def test_delete_by_namespace_requires_auth(self, client):
        """Test that delete by namespace requires admin authentication"""
        payload = {"namespace": "docs:test"}

        response = client.post("/v1/rag/delete/by_namespace", json=payload)
        assert response.status_code == 401

    def test_delete_by_namespace_empty_namespace(self, client):
        """Test deletion with empty namespace"""
        payload = {"namespace": ""}
        headers = {"X-HX-Admin-Key": "test-admin-key"}

        response = client.post(
            "/v1/rag/delete/by_namespace", json=payload, headers=headers
        )
        assert response.status_code == 422  # Validation error

    def test_delete_by_namespace_qdrant_error(self, client, mock_qdrant_error):
        """Test handling of Qdrant errors in namespace deletion"""
        payload = {"namespace": "docs:test"}
        headers = {"X-HX-Admin-Key": "test-admin-key"}

        response = client.post(
            "/v1/rag/delete/by_namespace", json=payload, headers=headers
        )
        assert response.status_code == 502


class TestDeleteByFilter:
    """Test delete by filter functionality"""

    def test_delete_by_filter_success(self, client, mock_successful_delete):
        """Test successful deletion by filter"""
        payload = {
            "must": [
                {"key": "namespace", "match": {"value": "docs:test"}},
                {"key": "source", "match": {"value": "test-source"}},
            ]
        }
        headers = {"X-HX-Admin-Key": "test-admin-key"}

        response = client.post(
            "/v1/rag/delete/by_filter", json=payload, headers=headers
        )

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["deleted"] == 3  # Count verified through before/after comparison
        assert "verified" in data["detail"]

    def test_delete_by_filter_namespace_only(self, client, mock_successful_delete):
        """Test deletion with namespace-only filter"""
        payload = {"must": [{"key": "namespace", "match": {"value": "docs:test"}}]}
        headers = {"X-HX-Admin-Key": "test-admin-key"}

        response = client.post(
            "/v1/rag/delete/by_filter", json=payload, headers=headers
        )

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"

    def test_delete_by_filter_requires_auth(self, client):
        """Test that delete by filter requires admin authentication"""
        payload = {"must": [{"key": "namespace", "match": {"value": "docs:test"}}]}

        response = client.post("/v1/rag/delete/by_filter", json=payload)
        assert response.status_code == 401

    def test_delete_by_filter_invalid_filter(self, client):
        """Test deletion with invalid filter format"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}

        # Empty filter
        response = client.post("/v1/rag/delete/by_filter", json={}, headers=headers)
        assert response.status_code == 422

        # Invalid filter structure
        payload = {"must": "invalid"}
        response = client.post(
            "/v1/rag/delete/by_filter", json=payload, headers=headers
        )
        assert response.status_code == 422


class TestSingleDocumentDelete:
    """Test single document delete via query parameter"""

    def test_delete_document_success(self, client, mock_successful_delete):
        """Test successful single document deletion"""
        doc_id = "99d1a84b-489b-089b-1fcf-1f126ef7df40"
        headers = {"X-HX-Admin-Key": "test-admin-key"}

        response = client.delete(f"/v1/rag/document?id={doc_id}", headers=headers)

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["deleted"] == 1
        assert data["detail"] is None

    def test_delete_document_requires_auth(self, client):
        """Test that single document delete requires admin authentication"""
        doc_id = "test-doc-id"

        response = client.delete(f"/v1/rag/document?id={doc_id}")
        assert response.status_code == 401

    def test_delete_document_missing_id(self, client):
        """Test deletion without document ID"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}

        response = client.delete("/v1/rag/document", headers=headers)
        assert response.status_code == 422  # Missing required query parameter

    def test_delete_document_empty_id(self, client):
        """Test deletion with empty document ID"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}

        response = client.delete("/v1/rag/document?id=", headers=headers)
        assert response.status_code == 422  # Validation error for empty string

    def test_delete_document_qdrant_error(self, client, mock_qdrant_error):
        """Test handling of Qdrant errors in single document deletion"""
        doc_id = "test-doc-id"
        headers = {"X-HX-Admin-Key": "test-admin-key"}

        response = client.delete(f"/v1/rag/document?id={doc_id}", headers=headers)
        assert response.status_code == 502


class TestDeleteResponseFormat:
    """Test response format consistency across all delete operations"""

    def test_response_format_consistency(self, client, mock_successful_delete):
        """Test that all delete endpoints return consistent response format"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}

        # Test all delete endpoints
        endpoints_and_payloads = [
            ("/v1/rag/delete/by_ids", {"ids": ["test-id"]}),
            ("/v1/rag/delete/by_namespace", {"namespace": "docs:test"}),
            (
                "/v1/rag/delete/by_filter",
                {"must": [{"key": "namespace", "match": {"value": "docs:test"}}]},
            ),
        ]

        for endpoint, payload in endpoints_and_payloads:
            response = client.post(endpoint, json=payload, headers=headers)
            assert response.status_code == 200

            data = response.json()
            # All responses should have these fields
            assert "status" in data
            assert "deleted" in data
            assert "detail" in data
            assert data["status"] == "ok"

        # Test single document delete
        response = client.delete("/v1/rag/document?id=test-id", headers=headers)
        assert response.status_code == 200
        data = response.json()
        assert "status" in data
        assert "deleted" in data
        assert "detail" in data
        assert data["status"] == "ok"


# Integration-style tests that simulate real scenarios
class TestDeleteIntegration:
    """Integration tests simulating real delete scenarios"""

    def test_full_delete_workflow(self, client, mock_successful_delete):
        """Test a complete delete workflow scenario"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}

        # 1. Delete specific documents by IDs
        response = client.post(
            "/v1/rag/delete/by_ids", json={"ids": ["doc1", "doc2"]}, headers=headers
        )
        assert response.status_code == 200
        assert response.json()["deleted"] == 2

        # 2. Delete remaining documents in namespace
        response = client.post(
            "/v1/rag/delete/by_namespace",
            json={"namespace": "docs:test"},
            headers=headers,
        )
        assert response.status_code == 200

        # 3. Clean up with filter-based deletion
        response = client.post(
            "/v1/rag/delete/by_filter",
            json={"must": [{"key": "source", "match": {"value": "cleanup"}}]},
            headers=headers,
        )
        assert response.status_code == 200

    def test_delete_nonexistent_resources(self, client, mock_successful_delete):
        """Test deletion of non-existent resources (should not fail)"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}

        # Delete non-existent IDs
        response = client.post(
            "/v1/rag/delete/by_ids",
            json={"ids": ["nonexistent-1", "nonexistent-2"]},
            headers=headers,
        )
        assert response.status_code == 200  # Should succeed even if nothing to delete

        # Delete from non-existent namespace
        response = client.post(
            "/v1/rag/delete/by_namespace",
            json={"namespace": "nonexistent:namespace"},
            headers=headers,
        )
        assert response.status_code == 200  # Should succeed even if namespace empty
