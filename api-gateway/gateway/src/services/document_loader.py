"""
Document Loader Service

SOLID-compliant service for processing various document formats into RAG-optimized chunks.
Supports Markdown and PDF with configurable chunking strategies and metadata enrichment.
"""

from __future__ import annotations
import io
import logging
import time
from typing import List, Dict, Any, Optional
from ..models.rag_upsert_models import UpsertDoc

logger = logging.getLogger(__name__)


def _chunk_text(text: str, chunk_chars: int = 1500, overlap: int = 200) -> List[str]:
    """
    Intelligent text chunking with configurable overlap for context preservation.
    
    Args:
        text: Input text to chunk
        chunk_chars: Maximum characters per chunk (256-8000)
        overlap: Characters to overlap between chunks (0-2000)
        
    Returns:
        List of text chunks with preserved context
    """
    text = text or ""
    
    if chunk_chars <= 0 or len(text) <= chunk_chars:
        return [text] if text else []
    
    chunks = []
    start = 0
    text_length = len(text)
    
    while start < text_length:
        end = min(text_length, start + chunk_chars)
        chunk = text[start:end]
        
        # Try to break at sentence boundaries for better chunking
        if end < text_length and chunk_chars > 100:
            # Look for sentence endings within the last 200 chars
            search_start = max(0, len(chunk) - 200)
            sentence_end = -1
            
            for delimiter in ['. ', '.\n', '!\n', '?\n', '! ', '? ']:
                pos = chunk.rfind(delimiter, search_start)
                if pos > sentence_end:
                    sentence_end = pos + len(delimiter)
            
            if sentence_end > 0:
                chunk = chunk[:sentence_end]
                end = start + len(chunk)
        
        if chunk.strip():  # Only add non-empty chunks
            chunks.append(chunk)
        
        if end >= text_length:
            break
            
        # Calculate next start position with overlap
        start = max(start + 1, end - overlap)
    
    logger.info(f"Chunked text into {len(chunks)} chunks (chars: {chunk_chars}, overlap: {overlap})")
    return chunks


def load_markdown(
    md_text: str, 
    namespace: str, 
    metadata: Optional[Dict[str, Any]] = None,
    chunk_chars: int = 1500, 
    overlap: int = 200
) -> List[UpsertDoc]:
    """
    Process Markdown text into RAG-optimized chunks with structure preservation.
    
    Args:
        md_text: Markdown content to process
        namespace: Document namespace for organization
        metadata: Additional metadata to attach
        chunk_chars: Characters per chunk
        overlap: Overlap between chunks
        
    Returns:
        List of UpsertDoc objects ready for embedding and storage
    """
    logger.info(f"Processing Markdown document: {len(md_text)} chars, namespace: {namespace}")
    
    chunks = _chunk_text(md_text, chunk_chars, overlap)
    docs = []
    
    for i, chunk in enumerate(chunks):
        # Enrich metadata with chunk information
        chunk_metadata = dict(metadata or {})
        chunk_metadata.update({
            "chunk_index": i,
            "total_chunks": len(chunks),
            "format": "markdown",
            "source_type": "text",
            "chunk_chars": len(chunk),
            "created_at": int(time.time())
        })
        
        # Add TTL support - default 30 days if not specified
        if "ttl_days" in chunk_metadata:
            ttl_seconds = chunk_metadata["ttl_days"] * 86400
            chunk_metadata["expires_at"] = int(time.time()) + ttl_seconds
        
        doc = UpsertDoc(
            text=chunk,
            namespace=namespace,
            metadata=chunk_metadata
        )
        docs.append(doc)
    
    logger.info(f"Created {len(docs)} document chunks from Markdown")
    return docs


def load_pdf_bytes(
    pdf_bytes: bytes, 
    namespace: str, 
    metadata: Optional[Dict[str, Any]] = None,
    chunk_chars: int = 1500, 
    overlap: int = 200
) -> List[UpsertDoc]:
    """
    Extract text from PDF bytes and process into RAG-optimized chunks.
    
    Args:
        pdf_bytes: PDF file content as bytes
        namespace: Document namespace for organization
        metadata: Additional metadata to attach
        chunk_chars: Characters per chunk
        overlap: Overlap between chunks
        
    Returns:
        List of UpsertDoc objects ready for embedding and storage
        
    Raises:
        HTTPException: If PDF processing fails
    """
    from fastapi import HTTPException
    
    logger.info(f"Processing PDF document: {len(pdf_bytes)} bytes, namespace: {namespace}")
    
    try:
        from pypdf import PdfReader
        
        # Read PDF from bytes
        pdf_stream = io.BytesIO(pdf_bytes)
        pdf_reader = PdfReader(pdf_stream)
        
        # Extract text from all pages
        full_text_parts = []
        page_count = len(pdf_reader.pages)
        
        for page_num, page in enumerate(pdf_reader.pages):
            try:
                page_text = page.extract_text() or ""
                if page_text.strip():
                    # Add page separator for context
                    page_header = f"\n--- Page {page_num + 1} ---\n"
                    full_text_parts.append(page_header + page_text)
                logger.debug(f"Extracted {len(page_text)} chars from page {page_num + 1}")
            except Exception as e:
                logger.warning(f"Failed to extract text from page {page_num + 1}: {e}")
                # Continue processing other pages
                continue
        
        if not full_text_parts:
            raise HTTPException(400, "No readable text found in PDF")
        
        full_text = "\n".join(full_text_parts)
        logger.info(f"Extracted {len(full_text)} total characters from {page_count} pages")
        
    except ImportError:
        raise HTTPException(500, "PDF processing library (pypdf) not available")
    except Exception as e:
        logger.error(f"PDF processing failed: {e}")
        raise HTTPException(400, f"Failed to process PDF: {str(e)}")
    
    # Chunk the extracted text
    chunks = _chunk_text(full_text, chunk_chars, overlap)
    docs = []
    
    for i, chunk in enumerate(chunks):
        # Enrich metadata with PDF-specific information
        chunk_metadata = dict(metadata or {})
        chunk_metadata.update({
            "chunk_index": i,
            "total_chunks": len(chunks),
            "format": "pdf",
            "source_type": "file",
            "page_count": page_count,
            "chunk_chars": len(chunk),
            "extracted_chars": len(full_text)
        })
        
        doc = UpsertDoc(
            text=chunk,
            namespace=namespace,
            metadata=chunk_metadata
        )
        docs.append(doc)
    
    logger.info(f"Created {len(docs)} document chunks from PDF")
    return docs


def validate_chunking_params(chunk_chars: int, overlap: int) -> None:
    """
    Validate chunking parameters to ensure reasonable values.
    
    Args:
        chunk_chars: Characters per chunk
        overlap: Overlap between chunks
        
    Raises:
        HTTPException: If parameters are invalid
    """
    from fastapi import HTTPException
    
    if chunk_chars < 100 or chunk_chars > 8000:
        raise HTTPException(400, "chunk_chars must be between 100 and 8000")
    
    if overlap < 0 or overlap > 2000:
        raise HTTPException(400, "overlap must be between 0 and 2000")
    
    if overlap >= chunk_chars:
        raise HTTPException(400, "overlap must be less than chunk_chars")
