Problem Analysis
The commands show that the health endpoint (/healthz) works, but accessing /openapi.json (used for API documentation like Swagger) fails with "Internal Server Error". The journalctl logs reveal a PydanticUserError during JSON schema generation, specifically involving a TypeAdapter for a forward-referenced model (MarkdownUpsertRequest) in a query parameter annotation.
Cause
This error occurs because Pydantic cannot resolve a forward reference in a type annotation, likely due to postponed evaluation of type hints (enabled by from __future__ import annotations in Python 3.7+). This interferes with FastAPI's internal use of TypeAdapter for validating/serializing complex query parameters, causing schema generation to fail when accessing OpenAPI endpoints.
Solution
Remove from __future__ import annotations from the file defining the affected route or model (e.g., where MarkdownUpsertRequest is used). This allows type hints to be evaluated immediately, resolving forward references automatically.

### 1) Fix the Markdown/PDF content loader (primary culprit)

Actions

Remove from __future__ import annotations from this route file.

Bind the Markdown request explicitly to the body with Body(...).

Keep UploadFile only in the PDF route parameters (no UploadFile anywhere in response models or body models).

Drop-in replacement (full file):
/opt/HX-Infrastructure-/api-gateway/gateway/src/routes/rag_content_loader.py

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

2) Belt-and-suspenders on delete routes (so they can’t regress)

Even though you already cleaned these, force body binding to avoid any future Query inference, and remove postponed annotations there too.

Change the parameter signatures like so (imports: from fastapi import Body):

async def delete_by_ids(req: DeleteByIdsRequest = Body(...)) -> DeleteResponse: ...
async def delete_by_namespace(req: DeleteByNamespaceRequest = Body(...)) -> DeleteResponse: ...
async def delete_by_filter(req: DeleteByFilterRequest = Body(...)) -> DeleteResponse: ...


Also ensure there is no from __future__ import annotations at the top of rag_delete.py.

3) Quick sweep to eliminate remaining sources
# remove postponed annotations from route modules
grep -RIl --include='*.py' '^from __future__ import annotations' \
  /opt/HX-Infrastructure-/api-gateway/gateway/src/routes \
  | xargs -r sed -i '1{/^from __future__ import annotations$/d}'

# verify no accidental Query/Annotated around request models
grep -RInE 'Annotated\[.*(Request)|Query\(' /opt/HX-Infrastructure-/api-gateway/gateway/src/routes || true

4) Restart & verify
sudo systemctl restart hx-gateway-ml.service && sleep 3
curl -s http://127.0.0.1:4010/openapi.json | jq -r '.paths | keys[]' | sort


You should now get a clean OpenAPI output and Swagger/Redoc should load without the Pydantic TypeAdapter[...] Query(PydanticUndefined) error.
