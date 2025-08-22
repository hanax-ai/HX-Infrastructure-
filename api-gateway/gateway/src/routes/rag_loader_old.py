"""
RAG Content Loader Routes

FastAPI routes for processing Markdown/PDF into RAG chunks.
Integrates with existing embedding + Qdrant upsert services.
"""
from __future__ import annotations

import json
import logging
import os
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from pydantic import BaseModel, Field

from ..services.security import require_rag_write, extract_auth_header
from ..services.document_loader import load_markdown, load_pdf_bytes, validate_chunking_params
from ..services.rag_upsert_helpers import auth_headers, embed_texts, qdrant_upsert, hash_id
from ..models.rag_upsert_models import UpsertResponse
from ..utils.structured_logging import log_request_response

logger = logging.getLogger(__name__)
router = APIRouter(tags=["rag"])

# ---- Env guardrails / defaults ---------------------------------------------
EMBEDDING_DIM = int(os.environ.get("EMBEDDING_DIM", "0"))          # 0 disables check
TEXT_PREVIEW_CHARS = int(os.environ.get("TEXT_PREVIEW_CHARS", "200"))
MAX_UPLOAD_MB = int(os.environ.get("MAX_UPLOAD_MB", "25"))
router = APIRouter(tags=["rag"])


class MarkdownUpsertRequest(BaseModel):
    """Request model for Markdown document processing."""
    
    text: str = Field(
        ..., 
        min_length=1, 
        max_length=1000000,  # 1MB limit
        description="Markdown content to process"
    )
    namespace: str = Field(
        ..., 
        min_length=1, 
        max_length=200,
        description="Document namespace for organization"
    )
    metadata: Optional[Dict[str, Any]] = Field(
        None,
        description="Additional metadata to attach to chunks"
    )
    chunk_chars: int = Field(
        default=1500, 
        ge=256, 
        le=8000,
        description="Characters per chunk (256-8000)"
    )
    overlap: int = Field(
        default=200, 
        ge=0, 
        le=2000,
        description="Overlap between chunks (0-2000)"
    )
    batch_size: int = Field(
        default=128, 
        ge=1, 
        le=1000,
        description="Embedding batch size (1-1000)"
    )


@router.post(
    "/v1/rag/upsert_markdown", 
    response_model=UpsertResponse, 
    dependencies=[Depends(require_rag_write)],
    summary="Process Markdown Document",
    description="Process Markdown text into RAG chunks with embedding and vector storage",
    responses={
        200: {
            "description": "Markdown successfully processed and stored",
            "content": {
                "application/json": {
                    "example": {
                        "status": "ok",
                        "upserted": 5,
                        "failed": 0,
                        "details": [{"result": "upserted 5 chunks"}]
                    }
                }
            }
        },
        400: {"description": "Invalid input - check text, namespace, or chunking parameters"},
        401: {"description": "Authentication required"},
        403: {"description": "Invalid admin key - write access required"},
        422: {"description": "Validation error"},
        502: {"description": "Embedding service or vector database error"}
    }
)
@log_request_response("upsert_markdown")
async def upsert_markdown(req: MarkdownUpsertRequest) -> UpsertResponse:
    """Process Markdown document into RAG chunks."""
    
    # Validate chunking parameters
    validate_chunking_params(req.chunk_chars, req.overlap)
    
    # Process Markdown into chunks
    try:
        docs = load_markdown(
            req.text, 
            req.namespace, 
            req.metadata, 
            req.chunk_chars, 
            req.overlap
        )
    except Exception as e:
        logger.error(f"Markdown processing failed: {e}")
        raise HTTPException(400, f"Failed to process Markdown: {str(e)}")
    
    if not docs:
        raise HTTPException(400, "No valid chunks generated from Markdown")
    
    # Extract text for embedding
    texts = [doc.text or "" for doc in docs]
    
    # Get embedding authentication headers
    headers = auth_headers(None)  # Uses EMBEDDING_AUTH_HEADER if configured
    
    # Generate embeddings
    try:
        vectors = await embed_texts(texts, headers)
    except HTTPException:
        raise  # Re-raise embedding errors as-is
    except Exception as e:
        logger.error(f"Embedding generation failed: {e}")
        raise HTTPException(502, f"Embedding service error: {str(e)}")
    
    # Build Qdrant points
    points = []
    for i, doc in enumerate(docs):
        vector = vectors[i]
        point_id = doc.id or hash_id(doc.namespace, doc.text or "")
        
        payload = dict(doc.metadata or {})
        if doc.namespace:
            payload["namespace"] = doc.namespace
        
        points.append({
            "id": point_id,
            "vector": vector,
            "payload": payload
        })
    
    # Upsert to Qdrant
    try:
        success, message = await qdrant_upsert(points)
    except Exception as e:
        logger.error(f"Qdrant upsert failed: {e}")
        raise HTTPException(502, f"Vector database error: {str(e)}")
    
    if success:
        logger.info(f"Successfully upserted {len(points)} Markdown chunks")
        return UpsertResponse(
            status="ok",
            upserted=len(points),
            failed=0,
            details=[{"result": f"upserted {len(points)} chunks"}]
        )
    else:
        logger.error(f"Qdrant upsert failed: {message}")
        raise HTTPException(502, f"Vector database upsert failed: {message[:300]}")


@router.post(
    "/v1/rag/upsert_pdf", 
    response_model=UpsertResponse, 
    dependencies=[Depends(require_rag_write)],
    summary="Process PDF Document",
    description="Upload and process PDF file into RAG chunks with embedding and vector storage",
    responses={
        200: {
            "description": "PDF successfully processed and stored",
            "content": {
                "application/json": {
                    "example": {
                        "status": "ok",
                        "upserted": 8,
                        "failed": 0,
                        "details": [{"result": "upserted 8 chunks from 3 pages"}]
                    }
                }
            }
        },
        400: {"description": "Invalid PDF file or processing parameters"},
        401: {"description": "Authentication required"},
        403: {"description": "Invalid admin key - write access required"},
        413: {"description": "PDF file too large"},
        422: {"description": "Validation error"},
        502: {"description": "Embedding service or vector database error"}
    }
)
@log_request_response("upsert_pdf")
async def upsert_pdf(
    namespace: str = Form(..., min_length=1, max_length=200, description="Document namespace"),
    metadata_json: Optional[str] = Form(None, description="JSON metadata for chunks"),
    chunk_chars: int = Form(1500, ge=256, le=8000, description="Characters per chunk"),
    overlap: int = Form(200, ge=0, le=2000, description="Overlap between chunks"),
    file: UploadFile = File(..., description="PDF file to process")
) -> UpsertResponse:
    """Process uploaded PDF file into RAG chunks."""
    
    # Validate file type
    if not file.content_type or file.content_type != 'application/pdf':
        raise HTTPException(400, "File must be a PDF (application/pdf)")
    
    # Validate chunking parameters
    validate_chunking_params(chunk_chars, overlap)
    
    # Parse metadata JSON if provided
    metadata = None
    if metadata_json:
        try:
            metadata = json.loads(metadata_json)
            if not isinstance(metadata, dict):
                raise ValueError("Metadata must be a JSON object")
        except Exception as e:
            raise HTTPException(400, f"Invalid metadata_json: {str(e)}")
    
    # Read PDF file
    try:
        pdf_bytes = await file.read()
        if len(pdf_bytes) == 0:
            raise HTTPException(400, "Empty PDF file")
        
        logger.info(f"Processing PDF upload: {file.filename}, {len(pdf_bytes)} bytes")
        
    except Exception as e:
        logger.error(f"Failed to read PDF file: {e}")
        raise HTTPException(400, f"Failed to read PDF file: {str(e)}")
    
    # Add file information to metadata
    if metadata is None:
        metadata = {}
    metadata.update({
        "filename": file.filename or "unknown.pdf",
        "file_size": len(pdf_bytes),
        "content_type": file.content_type
    })
    
    # Process PDF into chunks
    try:
        docs = load_pdf_bytes(pdf_bytes, namespace, metadata, chunk_chars, overlap)
    except HTTPException:
        raise  # Re-raise PDF processing errors as-is
    except Exception as e:
        logger.error(f"PDF processing failed: {e}")
        raise HTTPException(400, f"Failed to process PDF: {str(e)}")
    
    if not docs:
        raise HTTPException(400, "No readable text found in PDF")
    
    # Extract text for embedding
    texts = [doc.text or "" for doc in docs]
    
    # Get embedding authentication headers
    headers = auth_headers(None)
    
    # Generate embeddings
    try:
        vectors = await embed_texts(texts, headers)
    except HTTPException:
        raise  # Re-raise embedding errors as-is
    except Exception as e:
        logger.error(f"Embedding generation failed: {e}")
        raise HTTPException(502, f"Embedding service error: {str(e)}")
    
    # Build Qdrant points
    points = []
    for i, doc in enumerate(docs):
        vector = vectors[i]
        point_id = doc.id or hash_id(doc.namespace, doc.text or "")
        
        payload = dict(doc.metadata or {})
        if doc.namespace:
            payload["namespace"] = doc.namespace
        
        points.append({
            "id": point_id,
            "vector": vector,
            "payload": payload
        })
    
    # Upsert to Qdrant
    try:
        success, message = await qdrant_upsert(points)
    except Exception as e:
        logger.error(f"Qdrant upsert failed: {e}")
        raise HTTPException(502, f"Vector database error: {str(e)}")
    
    if success:
        page_count = metadata.get("page_count", "unknown")
        logger.info(f"Successfully upserted {len(points)} PDF chunks from {page_count} pages")
        return UpsertResponse(
            status="ok",
            upserted=len(points),
            failed=0,
            details=[{"result": f"upserted {len(points)} chunks from {page_count} pages"}]
        )
    else:
        logger.error(f"Qdrant upsert failed: {message}")
        raise HTTPException(502, f"Vector database upsert failed: {message[:300]}")
