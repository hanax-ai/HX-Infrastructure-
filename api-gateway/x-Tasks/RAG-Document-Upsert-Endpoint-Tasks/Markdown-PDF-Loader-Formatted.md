# RAG Content Loaders Implementation
## Markdown & PDF Document Processing Pipeline

### 🎯 Content Processing Strategy

**Why Content Loaders Are Essential:**
- **Structured Ingestion**: Convert documents into optimal RAG chunks
- **Format Preservation**: Maintain document structure and metadata
- **Scalable Processing**: Handle various document types with consistent interface
- **Quality Control**: Configurable chunking for optimal search performance

**Document Types Supported:**
- **Markdown**: Preserve structure, headings, and formatting context
- **PDF**: Text extraction with page-aware chunking
- **Plain Text**: Baseline processing with overlap management
- **Future**: HTML, DOCX, CSV, JSON document support

---

### 🔧 Chunking Strategy & Configuration

**Intelligent Text Chunking:**
- **Default Size**: 1500 characters (optimized for embedding models)
- **Overlap**: 200 characters (maintains context across chunks)
- **Boundary Awareness**: Preserve sentence/paragraph integrity
- **Metadata Enrichment**: Track chunk index, format, source info

**Configurable Parameters:**
- `chunk_chars`: 256-8000 characters (adjustable per document type)
- `overlap`: 0-2000 characters (context preservation)
- `batch_size`: 1-1000 chunks (processing optimization)

---

### 📚 Implementation Architecture

#### 1. Document Loader Service
```python
# gateway/src/services/document_loader.py
def _chunk_text(text: str, chunk_chars: int = 1500, overlap: int = 200) -> List[str]
def load_markdown(md_text: str, namespace: str, metadata: Dict, chunk_chars: int, overlap: int) -> List[UpsertDoc]
def load_pdf_bytes(pdf_bytes: bytes, namespace: str, metadata: Dict, chunk_chars: int, overlap: int) -> List[UpsertDoc]
```

#### 2. Content Processing Routes
```python
# gateway/src/routes/rag_loader.py
@router.post("/v1/rag/upsert_markdown")  # Markdown text processing
@router.post("/v1/rag/upsert_pdf")       # PDF file upload processing
```

#### 3. Request/Response Models
```python
class MarkdownUpsertRequest(BaseModel):
    text: str                    # Markdown content
    namespace: str              # Document namespace
    metadata: Dict[str, Any]    # Custom metadata
    chunk_chars: int = 1500     # Chunk size configuration
    overlap: int = 200          # Overlap configuration
    batch_size: int = 128       # Processing batch size
```

---

### 🚀 Document Processing Features

**Markdown Processing:**
- ✅ **Structure Preservation**: Maintain headings, lists, formatting
- ✅ **Metadata Enrichment**: Add chunk_index, format markers
- ✅ **Configurable Chunking**: Adjustable size and overlap
- ✅ **Namespace Isolation**: Multi-tenant document organization

**PDF Processing:**
- ✅ **Text Extraction**: Uses pypdf for reliable text extraction
- ✅ **Page-Aware Processing**: Maintains page boundaries in metadata
- ✅ **Binary Upload Support**: Handles file uploads directly
- ✅ **Error Resilience**: Graceful handling of extraction failures

**Common Features:**
- ✅ **Automatic Embedding**: Integrated with existing embedding pipeline
- ✅ **Qdrant Integration**: Direct vector database upsert
- ✅ **Authentication**: Write-scope admin key validation
- ✅ **Batch Processing**: Optimized for large document handling

---

### 🛡️ Security & Validation

**File Upload Security:**
- File size limits (configurable via FastAPI)
- Content type validation for PDF uploads
- Malicious content detection (basic)
- Secure temporary file handling

**Input Validation:**
- Chunk size boundaries (256-8000 characters)
- Overlap limits (0-2000 characters)
- Namespace format validation
- Metadata structure validation

**Error Handling:**
- PDF parsing failures (graceful degradation)
- Embedding service errors (proper propagation)
- Qdrant upsert failures (detailed error messages)
- Memory management for large files

---

### 📊 Processing Optimization

**Memory Management:**
- Streaming file uploads for large PDFs
- Chunked embedding processing
- Garbage collection for temporary objects
- Configurable batch sizes

**Performance Features:**
- Concurrent chunk processing
- Efficient text extraction algorithms
- Optimized vector database operations
- Progress tracking for large documents

---

### 🎮 Usage Examples

#### Markdown Document Upload
```bash
curl -X POST "http://127.0.0.1:4010/v1/rag/upsert_markdown" \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: sk-hx-admin-dev-2024" \
  -d '{
    "text": "# API Documentation\n\nThis is our comprehensive API guide...",
    "namespace": "docs:api",
    "metadata": {"source": "api-docs", "version": "v2.1"},
    "chunk_chars": 1200,
    "overlap": 150
  }'
```

#### PDF Document Upload
```bash
curl -X POST "http://127.0.0.1:4010/v1/rag/upsert_pdf" \
  -H "X-HX-Admin-Key: sk-hx-admin-dev-2024" \
  -F "file=@manual.pdf" \
  -F "namespace=docs:manual" \
  -F "metadata_json={\"source\":\"user-manual\",\"department\":\"support\"}" \
  -F "chunk_chars=1500" \
  -F "overlap=200"
```

---

### 🔄 Integration Points

**Existing RAG Pipeline:**
- Reuses `embed_texts()` service for vector generation
- Leverages `qdrant_upsert()` for database operations
- Integrates with `require_rag_write` authentication
- Uses existing `UpsertResponse` format for consistency

**Make Target Integration:**
```makefile
rag-test-markdown:     # Test markdown processing
rag-test-pdf:          # Test PDF upload processing
rag-verify-chunks:     # Verify chunking strategy
rag-test-loaders:      # Complete loader workflow test
```

---

### 🎯 Success Criteria

**Functional Requirements:**
- ✅ Markdown text processing with structure preservation
- ✅ PDF file upload and text extraction
- ✅ Configurable chunking with overlap management
- ✅ Metadata enrichment and namespace organization
- ✅ Integration with existing RAG pipeline

**Quality Requirements:**
- ✅ Robust error handling for processing failures
- ✅ Memory-efficient processing for large documents
- ✅ Consistent API responses with existing endpoints
- ✅ Comprehensive validation and security measures

**Operational Requirements:**
- ✅ Authentication integration with admin keys
- ✅ Structured logging for document processing
- ✅ Performance metrics and monitoring hooks
- ✅ Testing automation and validation workflows
