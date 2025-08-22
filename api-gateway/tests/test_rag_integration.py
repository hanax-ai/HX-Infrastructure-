# tests/test_rag_integration.py
"""
End-to-end integration tests for the complete RAG pipeline including:
- Content ingestion (markdown and PDF)
- Document storage and retrieval
- Document deletion by various methods
- Authentication and authorization
- Error handling and recovery

These tests mirror the manual validation commands we used to verify
the OpenAPI fixes and complete system functionality.
"""

import os
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from io import BytesIO
import json


@pytest.fixture(autouse=True)
def _prep_env(monkeypatch):
    """Set up test environment variables for integration tests"""
    monkeypatch.setenv("RAG_WRITE_KEY", "test-admin-key")
    monkeypatch.setenv("HX_ADMIN_KEY", "test-admin-key")
    monkeypatch.setenv("EMBEDDING_MODEL", "emb-premium")
    monkeypatch.setenv("EMBEDDING_DIM", "1024")
    monkeypatch.setenv("QDRANT_URL", "http://test-qdrant:6333")
    monkeypatch.setenv("QDRANT_COLLECTION", "test_collection")
    yield


@pytest.fixture
def mock_rag_services(monkeypatch):
    """Mock all RAG services for integration testing"""
    
    # Mock document processing
    def mock_load_markdown(text, namespace, metadata, chunk_chars, overlap):
        from types import SimpleNamespace
        # Simulate chunking - create multiple docs for longer text
        chunks = []
        text_chunks = [text[i:i+chunk_chars] for i in range(0, len(text), chunk_chars-overlap)]
        
        for i, chunk_text in enumerate(text_chunks):
            chunks.append(SimpleNamespace(
                id=f"chunk-{i}-{hash(chunk_text + namespace)}",
                text=chunk_text,
                namespace=namespace,
                metadata={**(metadata or {}), "chunk_index": i, "total_chunks": len(text_chunks)}
            ))
        return chunks
    
    def mock_load_pdf_bytes(pdf_bytes, namespace, metadata, chunk_chars, overlap):
        from types import SimpleNamespace
        # Simulate PDF text extraction and chunking
        extracted_text = f"Extracted PDF text from {len(pdf_bytes)} bytes"
        return [SimpleNamespace(
            id=f"pdf-chunk-{hash(extracted_text + namespace)}",
            text=extracted_text,
            namespace=namespace,
            metadata={**(metadata or {}), "file_size": len(pdf_bytes), "format": "pdf"}
        )]
    
    # Mock embedding service
    async def mock_embed_texts(texts, headers):
        return [[0.1 * i] * 1024 for i in range(len(texts))]
    
    # Mock Qdrant operations
    async def mock_qdrant_upsert(points):
        return True, f"Successfully upserted {len(points)} points"
    
    async def mock_delete_by_ids(point_ids):
        return True, f"Deleted {len(point_ids)} points"
    
    async def mock_delete_by_namespace(namespace):
        return True, f"Deleted all points in namespace: {namespace}"
    
    async def mock_delete_by_filter(filter_conditions):
        return True, "Deleted points matching filter"
    
    # Utility functions
    def mock_hash_id(namespace, text):
        return f"hash-{abs(hash(namespace + text))}"
    
    def mock_validate_chunking_params(chunk_chars, overlap):
        if not (256 <= chunk_chars <= 8000):
            raise ValueError("chunk_chars must be between 256 and 8000")
        if not (0 <= overlap <= 2000):
            raise ValueError("overlap must be between 0 and 2000")
    
    # Apply all mocks
    import gateway.src.routes.rag_content_loader as loader_route
    import gateway.src.routes.rag_delete as delete_route
    
    monkeypatch.setattr(loader_route, "load_markdown", mock_load_markdown)
    monkeypatch.setattr(loader_route, "load_pdf_bytes", mock_load_pdf_bytes)
    monkeypatch.setattr(loader_route, "embed_texts", mock_embed_texts)
    monkeypatch.setattr(loader_route, "qdrant_upsert", mock_qdrant_upsert)
    monkeypatch.setattr(loader_route, "hash_id", mock_hash_id)
    monkeypatch.setattr(loader_route, "validate_chunking_params", mock_validate_chunking_params)
    
    monkeypatch.setattr(delete_route, "delete_by_ids", mock_delete_by_ids)
    monkeypatch.setattr(delete_route, "delete_by_namespace", mock_delete_by_namespace)
    monkeypatch.setattr(delete_route, "delete_by_filter", mock_delete_by_filter)


class TestCompleteRAGWorkflow:
    """Test complete RAG workflows from content ingestion to deletion"""
    
    def test_full_rag_lifecycle(self, client, mock_rag_services):
        """Test the complete RAG lifecycle: create -> query -> delete"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        # Step 1: Ingest markdown content
        markdown_payload = {
            "text": "# Test Document\n\nThis is a comprehensive test document that validates our RAG pipeline. It contains multiple paragraphs and various formatting elements.",
            "namespace": "docs:integration-test",
            "metadata": {"source": "integration-test", "type": "validation"},
            "chunk_chars": 100,  # Small chunks to test chunking
            "overlap": 20
        }
        
        response = client.post("/v1/rag/upsert_markdown", json=markdown_payload, headers=headers)
        assert response.status_code == 200
        upsert_data = response.json()
        assert upsert_data["status"] == "ok"
        assert upsert_data["upserted"] > 0
        
        # Step 2: Ingest PDF content
        pdf_content = b"Mock PDF content for integration testing" * 10  # Make it longer
        files = {"file": ("integration-test.pdf", BytesIO(pdf_content), "application/pdf")}
        pdf_data = {
            "namespace": "docs:integration-test",
            "metadata_json": '{"source": "pdf-integration", "type": "validation"}',
            "chunk_chars": 200,
            "overlap": 30
        }
        
        response = client.post("/v1/rag/upsert_pdf", files=files, data=pdf_data, headers=headers)
        assert response.status_code == 200
        pdf_upsert_data = response.json()
        assert pdf_upsert_data["status"] == "ok"
        assert pdf_upsert_data["upserted"] > 0
        
        # Step 3: Delete specific documents by ID (simulating the real test we ran)
        mock_ids = ["test-chunk-1", "test-chunk-2"]
        delete_payload = {"ids": mock_ids}
        
        response = client.post("/v1/rag/delete/by_ids", json=delete_payload, headers=headers)
        assert response.status_code == 200
        delete_data = response.json()
        assert delete_data["status"] == "ok"
        assert delete_data["deleted"] == len(mock_ids)
        
        # Step 4: Delete by namespace (clean up remaining documents)
        namespace_payload = {"namespace": "docs:integration-test"}
        
        response = client.post("/v1/rag/delete/by_namespace", json=namespace_payload, headers=headers)
        assert response.status_code == 200
        namespace_delete_data = response.json()
        assert namespace_delete_data["status"] == "ok"
        assert namespace_delete_data["deleted"] == -1  # Count unknown for batch operations
    
    def test_authentication_workflow(self, client, mock_rag_services):
        """Test authentication across all RAG operations"""
        
        # Test operations without authentication (should all fail)
        unauthenticated_tests = [
            ("POST", "/v1/rag/upsert_markdown", {"text": "test", "namespace": "test"}),
            ("POST", "/v1/rag/delete/by_ids", {"ids": ["test"]}),
            ("POST", "/v1/rag/delete/by_namespace", {"namespace": "test"}),
            ("POST", "/v1/rag/delete/by_filter", {"must": []}),
            ("DELETE", "/v1/rag/document?id=test", None),
        ]
        
        for method, endpoint, payload in unauthenticated_tests:
            if method == "POST":
                if endpoint == "/v1/rag/upsert_pdf":
                    # Special handling for file upload
                    files = {"file": ("test.pdf", BytesIO(b"test"), "application/pdf")}
                    response = client.post(endpoint, files=files, data={"namespace": "test"})
                else:
                    response = client.post(endpoint, json=payload)
            else:
                response = client.delete(endpoint)
            
            assert response.status_code == 401, f"Expected 401 for {method} {endpoint}"
        
        # Test operations with correct authentication (should all succeed)
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        # Markdown upsert
        response = client.post("/v1/rag/upsert_markdown", 
                             json={"text": "# Auth Test", "namespace": "docs:auth"}, 
                             headers=headers)
        assert response.status_code == 200
        
        # PDF upsert
        files = {"file": ("auth-test.pdf", BytesIO(b"PDF content"), "application/pdf")}
        response = client.post("/v1/rag/upsert_pdf", 
                             files=files, 
                             data={"namespace": "docs:auth"}, 
                             headers=headers)
        assert response.status_code == 200
        
        # All delete operations
        delete_tests = [
            ("/v1/rag/delete/by_ids", {"ids": ["test-id"]}),
            ("/v1/rag/delete/by_namespace", {"namespace": "docs:auth"}),
            ("/v1/rag/delete/by_filter", {"must": [{"key": "namespace", "match": {"value": "docs:auth"}}]}),
        ]
        
        for endpoint, payload in delete_tests:
            response = client.post(endpoint, json=payload, headers=headers)
            assert response.status_code == 200, f"Expected 200 for {endpoint}"
        
        # Single document delete
        response = client.delete("/v1/rag/document?id=test-doc", headers=headers)
        assert response.status_code == 200
    
    def test_error_handling_workflow(self, client):
        """Test error handling across the RAG pipeline"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        # Test validation errors
        validation_tests = [
            # Markdown validation errors
            ("/v1/rag/upsert_markdown", {"text": "", "namespace": "test"}),  # Empty text
            ("/v1/rag/upsert_markdown", {"text": "test", "namespace": ""}),  # Empty namespace
            ("/v1/rag/upsert_markdown", {"text": "test", "namespace": "test", "chunk_chars": 100}),  # Invalid chunk_chars
            
            # Delete validation errors  
            ("/v1/rag/delete/by_ids", {"ids": "not-a-list"}),  # Invalid IDs type
            ("/v1/rag/delete/by_namespace", {"namespace": ""}),  # Empty namespace
            ("/v1/rag/delete/by_filter", {}),  # Empty filter
        ]
        
        for endpoint, payload in validation_tests:
            response = client.post(endpoint, json=payload, headers=headers)
            assert response.status_code == 422, f"Expected 422 for {endpoint} with invalid payload"
        
        # Test PDF validation errors
        # Wrong content type
        files = {"file": ("test.txt", BytesIO(b"not pdf"), "text/plain")}
        response = client.post("/v1/rag/upsert_pdf", 
                             files=files, 
                             data={"namespace": "test"}, 
                             headers=headers)
        assert response.status_code == 400
        
        # Empty PDF
        files = {"file": ("empty.pdf", BytesIO(b""), "application/pdf")}
        response = client.post("/v1/rag/upsert_pdf", 
                             files=files, 
                             data={"namespace": "test"}, 
                             headers=headers)
        assert response.status_code == 400
    
    def test_content_variations_workflow(self, client, mock_rag_services):
        """Test various content types and configurations"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        # Test different markdown content types
        markdown_variations = [
            {
                "text": "# Simple Header\n\nSimple content.",
                "namespace": "docs:simple",
                "description": "Simple markdown"
            },
            {
                "text": "# Complex Document\n\n## Section 1\n\nContent with **bold** and *italic* text.\n\n## Section 2\n\n- List item 1\n- List item 2\n\n```python\ncode_block = True\n```",
                "namespace": "docs:complex",
                "metadata": {"complexity": "high", "features": ["headers", "formatting", "code"]},
                "description": "Complex markdown with formatting"
            },
            {
                "text": "Very long document content. " * 100,  # Long content to test chunking
                "namespace": "docs:long",
                "chunk_chars": 500,
                "overlap": 50,
                "description": "Long document testing chunking"
            }
        ]
        
        for i, variation in enumerate(markdown_variations):
            description = variation.pop("description")
            response = client.post("/v1/rag/upsert_markdown", json=variation, headers=headers)
            assert response.status_code == 200, f"Failed for {description}"
            
            data = response.json()
            assert data["status"] == "ok", f"Failed status for {description}"
            assert data["upserted"] > 0, f"No documents upserted for {description}"
        
        # Test different PDF configurations
        pdf_variations = [
            {
                "content": b"Small PDF content",
                "filename": "small.pdf",
                "namespace": "docs:pdf-small",
                "description": "Small PDF"
            },
            {
                "content": b"Large PDF content with lots of text. " * 50,
                "filename": "large.pdf", 
                "namespace": "docs:pdf-large",
                "metadata": '{"size": "large", "pages": 10}',
                "chunk_chars": 300,
                "description": "Large PDF with metadata"
            }
        ]
        
        for variation in pdf_variations:
            description = variation.pop("description")
            content = variation.pop("content")
            filename = variation.pop("filename")
            
            files = {"file": (filename, BytesIO(content), "application/pdf")}
            data = {k: v for k, v in variation.items() if k != "metadata"}
            if "metadata" in variation:
                data["metadata_json"] = variation["metadata"]
            
            response = client.post("/v1/rag/upsert_pdf", files=files, data=data, headers=headers)
            assert response.status_code == 200, f"Failed for {description}"
            
            response_data = response.json()
            assert response_data["status"] == "ok", f"Failed status for {description}"
            assert response_data["upserted"] > 0, f"No documents upserted for {description}"


class TestOpenAPIValidation:
    """Test that OpenAPI generation works correctly (the original issue we fixed)"""
    
    def test_openapi_generation(self, client):
        """Test that OpenAPI JSON can be generated without errors"""
        response = client.get("/openapi.json")
        assert response.status_code == 200
        
        openapi_data = response.json()
        assert "openapi" in openapi_data
        assert "paths" in openapi_data
        
        # Verify that all our RAG endpoints are documented
        expected_paths = [
            "/v1/rag/upsert_markdown",
            "/v1/rag/upsert_pdf", 
            "/v1/rag/delete/by_ids",
            "/v1/rag/delete/by_namespace",
            "/v1/rag/delete/by_filter",
            "/v1/rag/document"
        ]
        
        documented_paths = openapi_data["paths"].keys()
        for path in expected_paths:
            assert path in documented_paths, f"Path {path} not found in OpenAPI documentation"
    
    def test_health_endpoint(self, client):
        """Test the health endpoint"""
        response = client.get("/healthz")
        assert response.status_code == 200
        
        data = response.json()
        assert "ok" in data
        assert data["ok"] is True


class TestResponseFormatConsistency:
    """Test that all endpoints return consistent response formats"""
    
    def test_upsert_response_format(self, client, mock_rag_services):
        """Test that all upsert endpoints return consistent format"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        # Test markdown upsert response
        markdown_response = client.post("/v1/rag/upsert_markdown", 
                                      json={"text": "# Test", "namespace": "docs:test"}, 
                                      headers=headers)
        assert markdown_response.status_code == 200
        markdown_data = markdown_response.json()
        
        # Test PDF upsert response
        files = {"file": ("test.pdf", BytesIO(b"test"), "application/pdf")}
        pdf_response = client.post("/v1/rag/upsert_pdf", 
                                 files=files, 
                                 data={"namespace": "docs:test"}, 
                                 headers=headers)
        assert pdf_response.status_code == 200
        pdf_data = pdf_response.json()
        
        # Both should have same response format
        required_fields = ["status", "upserted", "failed", "details"]
        for field in required_fields:
            assert field in markdown_data, f"Missing {field} in markdown response"
            assert field in pdf_data, f"Missing {field} in PDF response"
        
        # Check field types
        assert isinstance(markdown_data["upserted"], int)
        assert isinstance(pdf_data["upserted"], int)
        assert isinstance(markdown_data["failed"], int)
        assert isinstance(pdf_data["failed"], int)
        assert isinstance(markdown_data["details"], list)
        assert isinstance(pdf_data["details"], list)
    
    def test_delete_response_format(self, client, mock_rag_services):
        """Test that all delete endpoints return consistent format"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        delete_tests = [
            ("/v1/rag/delete/by_ids", {"ids": ["test-id"]}),
            ("/v1/rag/delete/by_namespace", {"namespace": "docs:test"}),
            ("/v1/rag/delete/by_filter", {"must": [{"key": "namespace", "match": {"value": "docs:test"}}]}),
        ]
        
        responses = []
        for endpoint, payload in delete_tests:
            response = client.post(endpoint, json=payload, headers=headers)
            assert response.status_code == 200
            responses.append(response.json())
        
        # Test single document delete
        single_response = client.delete("/v1/rag/document?id=test-doc", headers=headers)
        assert single_response.status_code == 200
        responses.append(single_response.json())
        
        # All responses should have consistent format
        required_fields = ["status", "deleted", "detail"]
        for i, response_data in enumerate(responses):
            for field in required_fields:
                assert field in response_data, f"Missing {field} in response {i}"
            
            assert response_data["status"] == "ok"
            assert isinstance(response_data["deleted"], int)


# Performance and load testing scenarios
class TestRAGPerformance:
    """Test RAG system under various load scenarios"""
    
    def test_batch_processing(self, client, mock_rag_services):
        """Test processing multiple documents in sequence"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        # Process multiple markdown documents
        for i in range(5):
            payload = {
                "text": f"# Document {i}\n\nThis is test document number {i} with content.",
                "namespace": f"docs:batch-{i}",
                "metadata": {"batch_index": i, "test": "batch-processing"}
            }
            
            response = client.post("/v1/rag/upsert_markdown", json=payload, headers=headers)
            assert response.status_code == 200
            
            data = response.json()
            assert data["status"] == "ok"
            assert data["upserted"] > 0
        
        # Clean up all batch documents
        for i in range(5):
            cleanup_payload = {"namespace": f"docs:batch-{i}"}
            response = client.post("/v1/rag/delete/by_namespace", json=cleanup_payload, headers=headers)
            assert response.status_code == 200
    
    def test_large_content_processing(self, client, mock_rag_services):
        """Test processing large documents"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        # Create large markdown content
        large_content = "# Large Document\n\n" + "This is a paragraph with substantial content. " * 200
        
        payload = {
            "text": large_content,
            "namespace": "docs:large-test",
            "chunk_chars": 1000,
            "overlap": 100,
            "batch_size": 64
        }
        
        response = client.post("/v1/rag/upsert_markdown", json=payload, headers=headers)
        assert response.status_code == 200
        
        data = response.json()
        assert data["status"] == "ok"
        assert data["upserted"] > 1  # Should create multiple chunks
        
        # Clean up
        cleanup_payload = {"namespace": "docs:large-test"}
        response = client.post("/v1/rag/delete/by_namespace", json=cleanup_payload, headers=headers)
        assert response.status_code == 200
