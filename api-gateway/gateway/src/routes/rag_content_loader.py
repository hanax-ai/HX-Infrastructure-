"""
RAG Content Loader Routes

FastAPI routes for processing various document formats (Markdown, PDF) into RAG chunks.
Integrates with existing embedding pipeline and vector database operations.
"""

# NOTE: Do NOT enable postponed annotations here; it breaks OpenAPI with Pydantic v2
# (i.e., do not use: from __future__ import annotations)

import json
import logging
from typing import Optional, Dict, Any

from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Form, Body
from pydantic import BaseModel, Field

from ..services.security import require_rag_write
from ..services.document_loader import load_markdown, load_pdf_bytes, validate_chunking_params
from ..services.rag_upsert_helpers import auth_headers, embed_texts, qdrant_upsert, hash_id
from ..models.rag_upsert_models import UpsertResponse
from ..utils.structured_logging import log_request_response

logger = logging.getLogger(__name__)
router = APIRouter(tags=["rag"])


class MarkdownUpsertRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=1_000_000, description="Markdown content")
    namespace: str = Field(..., min_length=1, max_length=200, description="Document namespace")
    metadata: Optional[Dict[str, Any]] = Field(None, description="Extra metadata")
    chunk_chars: int = Field(1500, ge=256, le=8000, description="Chars per chunk")
    overlap: int = Field(200, ge=0, le=2000, description="Overlap chars")
    batch_size: int = Field(128, ge=1, le=1000, description="Embedding batch size")


@router.post(
    "/v1/rag/upsert_markdown",
    response_model=UpsertResponse,
    dependencies=[Depends(require_rag_write)],
    summary="Process Markdown Document",
    description="Process Markdown text into RAG chunks with embedding and vector storage",
)
@log_request_response("upsert_markdown")
async def upsert_markdown(req: MarkdownUpsertRequest = Body(...)) -> UpsertResponse:
    validate_chunking_params(req.chunk_chars, req.overlap)

    try:
        docs = load_markdown(req.text, req.namespace, req.metadata, req.chunk_chars, req.overlap)
    except Exception as e:
        logger.error(f"Markdown processing failed: {e}")
        raise HTTPException(400, f"Failed to process Markdown: {str(e)}")

    if not docs:
        raise HTTPException(400, "No valid chunks generated from Markdown")

    texts = [doc.text or "" for doc in docs]
    headers = auth_headers(None)  # falls back to EMBEDDING_AUTH_HEADER if set

    try:
        vectors = await embed_texts(texts, headers)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Embedding generation failed: {e}")
        raise HTTPException(502, f"Embedding service error: {str(e)}")

    points = []
    for i, doc in enumerate(docs):
        vector = vectors[i]
        point_id = doc.id or hash_id(doc.namespace, doc.text or "")
        payload = dict(doc.metadata or {})
        if doc.namespace:
            payload["namespace"] = doc.namespace
        points.append({"id": point_id, "vector": vector, "payload": payload})

    try:
        success, message = await qdrant_upsert(points)
    except Exception as e:
        logger.error(f"Qdrant upsert failed: {e}")
        raise HTTPException(502, f"Vector database error: {str(e)}")

    if success:
        logger.info(f"Successfully upserted {len(points)} Markdown chunks")
        return UpsertResponse(status="ok", upserted=len(points), failed=0,
                              details=[{"result": f"upserted {len(points)} chunks"}])
    raise HTTPException(502, f"Vector database upsert failed: {message[:300]}")


@router.post(
    "/v1/rag/upsert_pdf",
    response_model=UpsertResponse,
    dependencies=[Depends(require_rag_write)],
    summary="Process PDF Document",
    description="Upload and process PDF file into RAG chunks with embedding and vector storage",
)
@log_request_response("upsert_pdf")
async def upsert_pdf(
    namespace: str = Form(..., min_length=1, max_length=200, description="Document namespace"),
    metadata_json: Optional[str] = Form(None, description="JSON metadata for chunks"),
    chunk_chars: int = Form(1500, ge=256, le=8000, description="Characters per chunk"),
    overlap: int = Form(200, ge=0, le=2000, description="Overlap between chunks"),
    file: UploadFile = File(..., description="PDF file to process"),
) -> UpsertResponse:
    if not file.content_type or file.content_type != "application/pdf":
        raise HTTPException(400, "File must be a PDF (application/pdf)")

    validate_chunking_params(chunk_chars, overlap)

    metadata = None
    if metadata_json:
        try:
            metadata = json.loads(metadata_json)
            if not isinstance(metadata, dict):
                raise ValueError("Metadata must be a JSON object")
        except Exception as e:
            raise HTTPException(400, f"Invalid metadata_json: {str(e)}")

    try:
        pdf_bytes = await file.read()
        if len(pdf_bytes) == 0:
            raise HTTPException(400, "Empty PDF file")
        logger.info(f"Processing PDF upload: {file.filename}, {len(pdf_bytes)} bytes")
    except Exception as e:
        logger.error(f"Failed to read PDF file: {e}")
        raise HTTPException(400, f"Failed to read PDF file: {str(e)}")

    if metadata is None:
        metadata = {}
    metadata.update({"filename": file.filename or "unknown.pdf",
                     "file_size": len(pdf_bytes),
                     "content_type": file.content_type})

    try:
        docs = load_pdf_bytes(pdf_bytes, namespace, metadata, chunk_chars, overlap)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"PDF processing failed: {e}")
        raise HTTPException(400, f"Failed to process PDF: {str(e)}")

    if not docs:
        raise HTTPException(400, "No readable text found in PDF")

    texts = [doc.text or "" for doc in docs]
    headers = auth_headers(None)

    try:
        vectors = await embed_texts(texts, headers)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Embedding generation failed: {e}")
        raise HTTPException(502, f"Embedding service error: {str(e)}")

    points = []
    for i, doc in enumerate(docs):
        vector = vectors[i]
        point_id = doc.id or hash_id(doc.namespace, doc.text or "")
        payload = dict(doc.metadata or {})
        if doc.namespace:
            payload["namespace"] = doc.namespace
        points.append({"id": point_id, "vector": vector, "payload": payload})

    try:
        success, message = await qdrant_upsert(points)
    except Exception as e:
        logger.error(f"Qdrant upsert failed: {e}")
        raise HTTPException(502, f"Vector database error: {str(e)}")

    if success:
        page_count = metadata.get("page_count", "unknown")
        logger.info(f"Successfully upserted {len(points)} PDF chunks from {page_count} pages")
        return UpsertResponse(status="ok", upserted=len(points), failed=0,
                              details=[{"result": f"upserted {len(points)} chunks from {page_count} pages"}])
    raise HTTPException(502, f"Vector database upsert failed: {message[:300]}")
