Nice work—this is close! A few issues + polish ideas, then a drop-in refactor.

Key review notes

Duplicate imports: UploadFile, File, Form appear twice in the import list.

Auth pass-through: auth_headers(None) ignores a caller’s Authorization. Prefer extract_auth_header(request) with fallback.

Batching not used: MarkdownUpsertRequest.batch_size isn’t applied. Large docs could time out; batch the embedding calls.

Response/detail consistency: Standardize detail keys/messages; include stable doc_id for traceability.

Preview + dims: Add optional TEXT_PREVIEW_CHARS and EMBEDDING_DIM guard (off by default).

File size: You advertise 413 but don’t enforce; add MAX_UPLOAD_MB.

Length checks: Verify vectors length matches docs.

Refactored routes (drop-in)
# gateway/src/routes/rag_content_loaders.py
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

class MarkdownUpsertRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=1_000_000, description="Markdown content")
    namespace: str = Field(..., min_length=1, max_length=200, description="Namespace")
    metadata: Optional[Dict[str, Any]] = Field(None, description="Extra metadata")
    chunk_chars: int = Field(default=1500, ge=256, le=8000, description="Chunk size")
    overlap: int = Field(default=200, ge=0, le=2000, description="Chunk overlap")
    batch_size: int = Field(default=128, ge=1, le=1000, description="Embedding batch size")

def _add_common_payload(doc_id: str, namespace: Optional[str], text: Optional[str], base: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    payload: Dict[str, Any] = (base.copy() if base else {})
    payload["doc_id"] = doc_id
    if namespace:
        payload["namespace"] = namespace
    if text and TEXT_PREVIEW_CHARS > 0:
        preview = text[:TEXT_PREVIEW_CHARS]
        if len(text) > TEXT_PREVIEW_CHARS:
            preview += "…"
        payload["text_preview"] = preview
    return payload

async def _embed_batched(all_texts: List[str], headers: Dict[str, str], batch_size: int) -> List[List[float]]:
    if not all_texts:
        return []
    vectors: List[List[float]] = []
    for i in range(0, len(all_texts), batch_size):
        chunk = all_texts[i : i + batch_size]
        chunk_vecs = await embed_texts(chunk, headers)
        vectors.extend(chunk_vecs)
    return vectors

def _check_vectors(vectors: List[List[float]]):
    if EMBEDDING_DIM > 0:
        for idx, v in enumerate(vectors):
            if len(v) != EMBEDDING_DIM:
                raise HTTPException(502, f"Embedding dim mismatch at index {idx}: got {len(v)}, expected {EMBEDDING_DIM}")

@router.post(
    "/v1/rag/upsert_markdown",
    response_model=UpsertResponse,
    dependencies=[Depends(require_rag_write)],
    summary="Process Markdown Document",
    description="Process Markdown into RAG chunks, embed, and upsert to vector DB.",
    responses={200: {"description": "Markdown processed and stored"}},
)
@log_request_response("upsert_markdown")
async def upsert_markdown(req: MarkdownUpsertRequest, request: Request) -> UpsertResponse:
    validate_chunking_params(req.chunk_chars, req.overlap)

    try:
        docs = load_markdown(req.text, req.namespace, req.metadata, req.chunk_chars, req.overlap)
    except Exception as e:
        logger.error(f"Markdown processing failed: {e}")
        raise HTTPException(400, f"Failed to process Markdown: {str(e)}")

    if not docs:
        raise HTTPException(400, "No valid chunks generated from Markdown")

    texts = [d.text or "" for d in docs]

    # Prefer caller Authorization, fallback to service auth
    headers = auth_headers(extract_auth_header(request))

    try:
        vectors = await _embed_batched(texts, headers, req.batch_size)
        if len(vectors) != len(docs):
            raise HTTPException(502, f"Embedding count mismatch: got {len(vectors)}, expected {len(docs)}")
        _check_vectors(vectors)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Embedding generation failed: {e}")
        raise HTTPException(502, f"Embedding service error: {str(e)}")

    points: List[Dict[str, Any]] = []
    for i, doc in enumerate(docs):
        point_id = doc.id or hash_id(doc.namespace, doc.text or "")
        payload = _add_common_payload(point_id, doc.namespace, doc.text, doc.metadata)
        points.append({"id": point_id, "vector": vectors[i], "payload": payload})

    try:
        ok, msg = await qdrant_upsert(points)
    except Exception as e:
        logger.error(f"Qdrant upsert failed: {e}")
        raise HTTPException(502, f"Vector database error: {str(e)}")

    if not ok:
        logger.error(f"Qdrant upsert failed: {msg}")
        raise HTTPException(502, f"Vector database upsert failed: {msg[:300]}")

    logger.info(f"Successfully upserted {len(points)} Markdown chunks")
    return UpsertResponse(status="ok", upserted=len(points), failed=0, details=[{"result": f"upserted {len(points)} chunks"}])

@router.post(
    "/v1/rag/upsert_pdf",
    response_model=UpsertResponse,
    dependencies=[Depends(require_rag_write)],
    summary="Process PDF Document",
    description="Upload a PDF; extract text, chunk, embed, and upsert to vector DB.",
    responses={200: {"description": "PDF processed and stored"}, 413: {"description": "PDF file too large"}},
)
@log_request_response("upsert_pdf")
async def upsert_pdf(
    request: Request,
    namespace: str = Form(..., min_length=1, max_length=200, description="Namespace"),
    metadata_json: Optional[str] = Form(None, description="JSON metadata for chunks"),
    chunk_chars: int = Form(1500, ge=256, le=8000, description="Characters per chunk"),
    overlap: int = Form(200, ge=0, le=2000, description="Overlap between chunks"),
    batch_size: int = Form(128, ge=1, le=1000, description="Embedding batch size"),
    file: UploadFile = File(..., description="PDF file"),
) -> UpsertResponse:
    if file.content_type != "application/pdf":
        raise HTTPException(400, "File must be a PDF (application/pdf)")

    validate_chunking_params(chunk_chars, overlap)

    metadata: Optional[Dict[str, Any]] = None
    if metadata_json:
        try:
            metadata = json.loads(metadata_json)
            if not isinstance(metadata, dict):
                raise ValueError("Metadata must be a JSON object")
        except Exception as e:
            raise HTTPException(400, f"Invalid metadata_json: {str(e)}")

    try:
        pdf_bytes = await file.read()
    except Exception as e:
        logger.error(f"Failed to read PDF: {e}")
        raise HTTPException(400, f"Failed to read PDF file: {str(e)}")

    if len(pdf_bytes) == 0:
        raise HTTPException(400, "Empty PDF file")

    max_bytes = MAX_UPLOAD_MB * 1024 * 1024
    if len(pdf_bytes) > max_bytes:
        raise HTTPException(413, f"PDF larger than {MAX_UPLOAD_MB} MB")

    meta = (metadata or {}).copy()
    meta.update({"filename": file.filename or "unknown.pdf", "file_size": len(pdf_bytes), "content_type": file.content_type})

    try:
        docs = load_pdf_bytes(pdf_bytes, namespace, meta, chunk_chars, overlap)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"PDF processing failed: {e}")
        raise HTTPException(400, f"Failed to process PDF: {str(e)}")

    if not docs:
        raise HTTPException(400, "No readable text found in PDF")

    texts = [d.text or "" for d in docs]
    headers = auth_headers(extract_auth_header(request))

    try:
        vectors = await _embed_batched(texts, headers, batch_size)
        if len(vectors) != len(docs):
            raise HTTPException(502, f"Embedding count mismatch: got {len(vectors)}, expected {len(docs)}")
        _check_vectors(vectors)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Embedding generation failed: {e}")
        raise HTTPException(502, f"Embedding service error: {str(e)}")

    points: List[Dict[str, Any]] = []
    for i, doc in enumerate(docs):
        point_id = doc.id or hash_id(doc.namespace, doc.text or "")
        payload = _add_common_payload(point_id, doc.namespace, doc.text, doc.metadata)
        points.append({"id": point_id, "vector": vectors[i], "payload": payload})

    try:
        ok, msg = await qdrant_upsert(points)
    except Exception as e:
        logger.error(f"Qdrant upsert failed: {e}")
        raise HTTPException(502, f"Vector database error: {str(e)}")

    if not ok:
        logger.error(f"Qdrant upsert failed: {msg}")
        raise HTTPException(502, f"Vector database upsert failed: {msg[:300]}")

    page_count = (meta or {}).get("page_count", "unknown")
    logger.info(f"Successfully upserted {len(points)} PDF chunks from {page_count} pages")
    return UpsertResponse(
        status="ok",
        upserted=len(points),
        failed=0,
        details=[{"result": f"upserted {len(points)} chunks from {page_count} pages"}],
    )

Env you can set (optional)

EMBEDDING_DIM=1024 (or 1536) to enforce vector length

TEXT_PREVIEW_CHARS=200 to tweak previews (0 to disable)

MAX_UPLOAD_MB=25 to enforce upload size limit

This keeps your behavior intact, removes the earlier FastAPI/Pydantic gotchas, and adds guardrails for production.

ChatGPT can make mistakes. OpenAI doesn't use Hana-X work