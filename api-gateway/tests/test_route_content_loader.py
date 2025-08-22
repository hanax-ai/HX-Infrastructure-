# tests/test_route_content_loader.py
"""
Test suite for RAG content loader operations including:
- Markdown document processing
- PDF document processing
- Authentication and validation
- Error handling for various content types
"""

import os
import pytest
from unittest.mock import AsyncMock, MagicMock
from fastapi import HTTPException
from io import BytesIO

# Import the route modules we're testing
import gateway.src.routes.rag_content_loader as loader_route


@pytest.fixture(autouse=True)
def _prep_env(monkeypatch):
    """Set up test environment variables"""
    monkeypatch.setenv("RAG_WRITE_KEY", "test-admin-key")
    monkeypatch.setenv("HX_ADMIN_KEY", "test-admin-key")
    monkeypatch.setenv("EMBEDDING_MODEL", "emb-premium")
    monkeypatch.setenv("EMBEDDING_DIM", "1024")
    monkeypatch.setenv("QDRANT_URL", "http://test-qdrant:6333")
    monkeypatch.setenv("QDRANT_COLLECTION", "test_collection")
    yield


@pytest.fixture
def mock_successful_processing(monkeypatch):
    """Mock successful document processing and embedding"""
    
    def fake_load_markdown(text, namespace, metadata, chunk_chars, overlap):
        """Mock markdown loader that returns mock documents"""
        from types import SimpleNamespace
        docs = [
            SimpleNamespace(
                id="test-chunk-1",
                text="Test markdown content chunk 1",
                namespace=namespace,
                metadata=metadata or {"source": "markdown"}
            )
        ]
        return docs
    
    def fake_load_pdf_bytes(pdf_bytes, namespace, metadata, chunk_chars, overlap):
        """Mock PDF loader that returns mock documents"""
        from types import SimpleNamespace
        docs = [
            SimpleNamespace(
                id="test-pdf-chunk-1", 
                text="Test PDF content chunk 1",
                namespace=namespace,
                metadata=metadata or {"source": "pdf"}
            )
        ]
        return docs
    
    async def fake_embed_texts(texts, headers):
        """Mock embedding service that returns test vectors"""
        return [[0.1] * 1024 for _ in texts]
    
    async def fake_qdrant_upsert(points):
        """Mock Qdrant upsert that always succeeds"""
        return True, f"Successfully upserted {len(points)} points"
    
    def fake_hash_id(namespace, text):
        """Mock hash ID generation"""
        return f"hash-{hash(namespace + text)}"
    
    def fake_validate_chunking_params(chunk_chars, overlap):
        """Mock chunking parameter validation"""
        if chunk_chars < 256 or chunk_chars > 8000:
            raise ValueError("Invalid chunk_chars")
        if overlap < 0 or overlap > 2000:
            raise ValueError("Invalid overlap")
    
    monkeypatch.setattr(loader_route, "load_markdown", fake_load_markdown)
    monkeypatch.setattr(loader_route, "load_pdf_bytes", fake_load_pdf_bytes)
    monkeypatch.setattr(loader_route, "embed_texts", fake_embed_texts)
    monkeypatch.setattr(loader_route, "qdrant_upsert", fake_qdrant_upsert)
    monkeypatch.setattr(loader_route, "hash_id", fake_hash_id)
    monkeypatch.setattr(loader_route, "validate_chunking_params", fake_validate_chunking_params)


@pytest.fixture 
def mock_processing_errors(monkeypatch):
    """Mock processing errors for error handling tests"""
    
    def failing_load_markdown(*args, **kwargs):
        raise Exception("Markdown processing failed")
    
    def failing_load_pdf(*args, **kwargs):
        raise Exception("PDF processing failed")
    
    async def failing_embed_texts(*args, **kwargs):
        raise HTTPException(502, "Embedding service unavailable")
    
    async def failing_qdrant_upsert(*args, **kwargs):
        raise Exception("Qdrant upsert failed")
    
    monkeypatch.setattr(loader_route, "load_markdown", failing_load_markdown)
    monkeypatch.setattr(loader_route, "load_pdf_bytes", failing_load_pdf)
    monkeypatch.setattr(loader_route, "embed_texts", failing_embed_texts)
    monkeypatch.setattr(loader_route, "qdrant_upsert", failing_qdrant_upsert)


class TestMarkdownLoader:
    """Test markdown document loading and processing"""
    
    def test_upsert_markdown_success(self, client, mock_successful_processing):
        """Test successful markdown document processing"""
        payload = {
            "text": "# Test Document\n\nThis is a test markdown document with **bold** text.",
            "namespace": "docs:test",
            "metadata": {"source": "test", "author": "pytest"},
            "chunk_chars": 1500,
            "overlap": 200,
            "batch_size": 128
        }
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        response = client.post("/v1/rag/upsert_markdown", json=payload, headers=headers)
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["upserted"] == 1
        assert data["failed"] == 0
        assert len(data["details"]) > 0
    
    def test_upsert_markdown_minimal(self, client, mock_successful_processing):
        """Test markdown processing with minimal required fields"""
        payload = {
            "text": "# Minimal Test\n\nMinimal content.",
            "namespace": "docs:minimal"
        }
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        response = client.post("/v1/rag/upsert_markdown", json=payload, headers=headers)
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["upserted"] == 1
    
    def test_upsert_markdown_requires_auth(self, client):
        """Test that markdown upsert requires admin authentication"""
        payload = {
            "text": "# Test\n\nContent",
            "namespace": "docs:test"
        }
        
        # No auth header
        response = client.post("/v1/rag/upsert_markdown", json=payload)
        assert response.status_code == 401
        
        # Wrong auth key
        headers = {"X-HX-Admin-Key": "wrong-key"}
        response = client.post("/v1/rag/upsert_markdown", json=payload, headers=headers)
        assert response.status_code == 401
    
    def test_upsert_markdown_validation_errors(self, client):
        """Test markdown upsert validation errors"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        # Empty text
        payload = {"text": "", "namespace": "docs:test"}
        response = client.post("/v1/rag/upsert_markdown", json=payload, headers=headers)
        assert response.status_code == 422
        
        # Empty namespace
        payload = {"text": "# Test", "namespace": ""}
        response = client.post("/v1/rag/upsert_markdown", json=payload, headers=headers)
        assert response.status_code == 422
        
        # Text too long (over 1M chars)
        payload = {"text": "a" * 1_000_001, "namespace": "docs:test"}
        response = client.post("/v1/rag/upsert_markdown", json=payload, headers=headers)
        assert response.status_code == 422
        
        # Invalid chunk_chars
        payload = {"text": "# Test", "namespace": "docs:test", "chunk_chars": 100}
        response = client.post("/v1/rag/upsert_markdown", json=payload, headers=headers)
        assert response.status_code == 422
        
        # Invalid overlap
        payload = {"text": "# Test", "namespace": "docs:test", "overlap": 3000}
        response = client.post("/v1/rag/upsert_markdown", json=payload, headers=headers)
        assert response.status_code == 422
    
    def test_upsert_markdown_processing_error(self, client, mock_processing_errors):
        """Test handling of markdown processing errors"""
        payload = {
            "text": "# Test\n\nContent",
            "namespace": "docs:test"
        }
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        response = client.post("/v1/rag/upsert_markdown", json=payload, headers=headers)
        
        assert response.status_code == 400
        assert "Failed to process Markdown" in response.text
    
    def test_upsert_markdown_embedding_error(self, client, mock_processing_errors):
        """Test handling of embedding service errors"""
        # Override just the markdown loader to succeed, but embedding fails
        def working_load_markdown(text, namespace, metadata, chunk_chars, overlap):
            from types import SimpleNamespace
            return [SimpleNamespace(id="test", text="content", namespace=namespace, metadata=metadata)]
        
        import gateway.src.routes.rag_content_loader as loader_route
        loader_route.load_markdown = working_load_markdown
        
        payload = {
            "text": "# Test\n\nContent",
            "namespace": "docs:test"
        }
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        response = client.post("/v1/rag/upsert_markdown", json=payload, headers=headers)
        
        assert response.status_code == 502
        assert "Embedding service unavailable" in response.text


class TestPDFLoader:
    """Test PDF document loading and processing"""
    
    def test_upsert_pdf_success(self, client, mock_successful_processing):
        """Test successful PDF document processing"""
        # Create a mock PDF file
        pdf_content = b"Mock PDF content for testing"
        
        files = {"file": ("test.pdf", BytesIO(pdf_content), "application/pdf")}
        data = {
            "namespace": "docs:pdf-test",
            "metadata_json": '{"source": "test-pdf", "author": "pytest"}',
            "chunk_chars": 1500,
            "overlap": 200
        }
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        response = client.post("/v1/rag/upsert_pdf", files=files, data=data, headers=headers)
        
        assert response.status_code == 200
        response_data = response.json()
        assert response_data["status"] == "ok"
        assert response_data["upserted"] == 1
        assert response_data["failed"] == 0
    
    def test_upsert_pdf_minimal(self, client, mock_successful_processing):
        """Test PDF processing with minimal required fields"""
        pdf_content = b"Minimal PDF content"
        
        files = {"file": ("minimal.pdf", BytesIO(pdf_content), "application/pdf")}
        data = {"namespace": "docs:minimal-pdf"}
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        response = client.post("/v1/rag/upsert_pdf", files=files, data=data, headers=headers)
        
        assert response.status_code == 200
        response_data = response.json()
        assert response_data["status"] == "ok"
    
    def test_upsert_pdf_requires_auth(self, client):
        """Test that PDF upsert requires admin authentication"""
        pdf_content = b"Test PDF content"
        files = {"file": ("test.pdf", BytesIO(pdf_content), "application/pdf")}
        data = {"namespace": "docs:test"}
        
        # No auth header
        response = client.post("/v1/rag/upsert_pdf", files=files, data=data)
        assert response.status_code == 401
    
    def test_upsert_pdf_content_type_validation(self, client):
        """Test PDF content type validation"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        # Wrong content type
        files = {"file": ("test.txt", BytesIO(b"Not a PDF"), "text/plain")}
        data = {"namespace": "docs:test"}
        response = client.post("/v1/rag/upsert_pdf", files=files, data=data, headers=headers)
        assert response.status_code == 400
        assert "File must be a PDF" in response.text
        
        # No content type
        files = {"file": ("test.pdf", BytesIO(b"PDF content"), None)}
        response = client.post("/v1/rag/upsert_pdf", files=files, data=data, headers=headers)
        assert response.status_code == 400
    
    def test_upsert_pdf_empty_file(self, client):
        """Test handling of empty PDF files"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        files = {"file": ("empty.pdf", BytesIO(b""), "application/pdf")}
        data = {"namespace": "docs:test"}
        
        response = client.post("/v1/rag/upsert_pdf", files=files, data=data, headers=headers)
        assert response.status_code == 400
        assert "Empty PDF file" in response.text
    
    def test_upsert_pdf_invalid_metadata(self, client):
        """Test handling of invalid JSON metadata"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        pdf_content = b"PDF content"
        
        files = {"file": ("test.pdf", BytesIO(pdf_content), "application/pdf")}
        data = {
            "namespace": "docs:test",
            "metadata_json": "invalid json"
        }
        
        response = client.post("/v1/rag/upsert_pdf", files=files, data=data, headers=headers)
        assert response.status_code == 400
        assert "Invalid metadata_json" in response.text
        
        # Non-object JSON
        data["metadata_json"] = "\"string\""
        response = client.post("/v1/rag/upsert_pdf", files=files, data=data, headers=headers)
        assert response.status_code == 400
        assert "Metadata must be a JSON object" in response.text
    
    def test_upsert_pdf_processing_error(self, client, mock_processing_errors):
        """Test handling of PDF processing errors"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        pdf_content = b"PDF content"
        
        files = {"file": ("test.pdf", BytesIO(pdf_content), "application/pdf")}
        data = {"namespace": "docs:test"}
        
        response = client.post("/v1/rag/upsert_pdf", files=files, data=data, headers=headers)
        assert response.status_code == 400
        assert "Failed to process PDF" in response.text


class TestContentLoaderIntegration:
    """Integration tests for content loader functionality"""
    
    def test_markdown_and_pdf_workflow(self, client, mock_successful_processing):
        """Test processing both markdown and PDF in sequence"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        # 1. Process markdown document
        markdown_payload = {
            "text": "# Integration Test\n\nThis tests the markdown workflow.",
            "namespace": "docs:integration",
            "metadata": {"type": "markdown", "test": "integration"}
        }
        
        response = client.post("/v1/rag/upsert_markdown", json=markdown_payload, headers=headers)
        assert response.status_code == 200
        markdown_data = response.json()
        assert markdown_data["status"] == "ok"
        
        # 2. Process PDF document
        pdf_content = b"Mock PDF for integration test"
        files = {"file": ("integration.pdf", BytesIO(pdf_content), "application/pdf")}
        pdf_data = {
            "namespace": "docs:integration",
            "metadata_json": '{"type": "pdf", "test": "integration"}'
        }
        
        response = client.post("/v1/rag/upsert_pdf", files=files, data=pdf_data, headers=headers)
        assert response.status_code == 200
        pdf_response_data = response.json()
        assert pdf_response_data["status"] == "ok"
    
    def test_chunking_parameter_variations(self, client, mock_successful_processing):
        """Test different chunking parameter combinations"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        base_text = "# Test\n\n" + "This is test content. " * 100  # Make it long enough to chunk
        
        chunking_configs = [
            {"chunk_chars": 500, "overlap": 50},
            {"chunk_chars": 1000, "overlap": 100},
            {"chunk_chars": 2000, "overlap": 300},
        ]
        
        for i, config in enumerate(chunking_configs):
            payload = {
                "text": base_text,
                "namespace": f"docs:chunking-{i}",
                **config
            }
            
            response = client.post("/v1/rag/upsert_markdown", json=payload, headers=headers)
            assert response.status_code == 200
            data = response.json()
            assert data["status"] == "ok"
    
    def test_large_batch_processing(self, client, mock_successful_processing):
        """Test processing with different batch sizes"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        # Create content that will generate multiple chunks
        large_text = "# Large Document\n\n" + "Content paragraph. " * 200
        
        batch_sizes = [32, 64, 128, 256]
        
        for batch_size in batch_sizes:
            payload = {
                "text": large_text,
                "namespace": f"docs:batch-{batch_size}",
                "batch_size": batch_size,
                "chunk_chars": 500  # Small chunks to generate many
            }
            
            response = client.post("/v1/rag/upsert_markdown", json=payload, headers=headers)
            assert response.status_code == 200
            data = response.json()
            assert data["status"] == "ok"
    
    def test_error_recovery_scenarios(self, client, mock_successful_processing):
        """Test various error recovery scenarios"""
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        # Test with content that produces no chunks
        def no_chunks_loader(*args, **kwargs):
            return []  # No documents generated
        
        import gateway.src.routes.rag_content_loader as loader_route
        original_loader = loader_route.load_markdown
        loader_route.load_markdown = no_chunks_loader
        
        payload = {
            "text": "# Empty Result\n\nThis should produce no chunks.",
            "namespace": "docs:empty"
        }
        
        response = client.post("/v1/rag/upsert_markdown", json=payload, headers=headers)
        assert response.status_code == 400
        assert "No valid chunks generated" in response.text
        
        # Restore original loader
        loader_route.load_markdown = original_loader


class TestContentLoaderResponseFormat:
    """Test response format consistency for content loader endpoints"""
    
    def test_markdown_response_format(self, client, mock_successful_processing):
        """Test markdown endpoint response format"""
        payload = {
            "text": "# Test\n\nContent",
            "namespace": "docs:test"
        }
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        response = client.post("/v1/rag/upsert_markdown", json=payload, headers=headers)
        assert response.status_code == 200
        
        data = response.json()
        # Check required fields
        assert "status" in data
        assert "upserted" in data  
        assert "failed" in data
        assert "details" in data
        
        # Check field types and values
        assert data["status"] == "ok"
        assert isinstance(data["upserted"], int)
        assert isinstance(data["failed"], int)
        assert isinstance(data["details"], list)
        assert data["upserted"] > 0
        assert data["failed"] == 0
    
    def test_pdf_response_format(self, client, mock_successful_processing):
        """Test PDF endpoint response format"""
        pdf_content = b"PDF content"
        files = {"file": ("test.pdf", BytesIO(pdf_content), "application/pdf")}
        data = {"namespace": "docs:test"}
        headers = {"X-HX-Admin-Key": "test-admin-key"}
        
        response = client.post("/v1/rag/upsert_pdf", files=files, data=data, headers=headers)
        assert response.status_code == 200
        
        response_data = response.json()
        # Check required fields (same as markdown)
        assert "status" in response_data
        assert "upserted" in response_data
        assert "failed" in response_data
        assert "details" in response_data
        
        # Check field values
        assert response_data["status"] == "ok"
        assert response_data["upserted"] > 0
        assert response_data["failed"] == 0
