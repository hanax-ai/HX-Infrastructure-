### Step 1

cd /opt/HX-Infrastructure-/api-gateway/gateway/src/routes
cat << 'EOF' > rag_content_loader.py
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
EOF
sed -i '/from __future__ import annotations/d' rag_delete.py
sed -i 's/async def delete_by_ids(/async def delete_by_ids(req: DeleteByIdsRequest = Body(...)) /g' rag_delete.py
sed -i 's/async def delete_by_namespace(/async def delete_by_namespace(req: DeleteByNamespaceRequest = Body(...)) /g' rag_delete.py
sed -i 's/async def delete_by_filter(/async def delete_by_filter(req: DeleteByFilterRequest = Body(...)) /g' rag_delete.py
sed -i 's/async def delete_document(id: str = Query(..., min_length=1))/async def delete_document(id: str = Query(..., min_length=1, description="Document ID to delete")) /g' rag_delete.py
cd /opt/HX-Infrastructure-/api-gateway/gateway
sudo systemctl restart hx-gateway-ml.service && sleep 3
curl -s http://127.0.0.1:4010/openapi.json | jq -r '.paths | keys[]' | sort

### Step 2

cd /opt/HX-Infrastructure-/api-gateway/gateway/src/routes
sed -i 's/from fastapi import APIRouter, Depends, HTTPException, Query/from fastapi import APIRouter, Depends, HTTPException, Query, Body/g' rag_delete.py
cd /opt/HX-Infrastructure-/api-gateway/gateway/src
cat << 'EOF' > app.py
# gateway/src/app.py
import os
from fastapi import FastAPI, Request
from starlette.responses import JSONResponse, Response

from .gateway_pipeline import GatewayPipeline

# Routers
from .routes.rag import router as rag_router
from .routes.rag_upsert import router as rag_upsert_router
from .routes.rag_delete import router as rag_delete_router
from .routes.rag_content_loader import router as rag_loader_router

def build_app() -> FastAPI:
    app = FastAPI(title="HX API Gateway")
    pipeline = GatewayPipeline()

    # Mount all RAG routers explicitly
    app.include_router(rag_router, tags=["rag"])
    app.include_router(rag_upsert_router, tags=["rag"])
    app.include_router(rag_delete_router, tags=["rag"])
    app.include_router(rag_loader_router, tags=["rag"])

    @app.get("/healthz")
    async def healthz():
        return {"ok": True}

    # Keep the catch-all proxy last
    @app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"])
    async def _all(request: Request, path: str) -> Response:
        resp: Response | None = await pipeline.process_request(request)
        return resp or JSONResponse({"detail": "Not Found"}, status_code=404)

    return app
EOF
cd /opt/HX-Infrastructure-/api-gateway/gateway
sudo systemctl restart hx-gateway-ml.service && sleep 3
curl -s http://127.0.0.1:4010/openapi.json | jq -r '.paths | keys[]' | sort
grep -RIn "from __future__ import annotations" /opt/HX-Infrastructure-/api-gateway/gateway/src/routes || echo "✅ no postponed annotations in routes"
grep -RInE 'Annotated\[.*Request|Query\(' /opt/HX-Infrastructure-/api-gateway/gateway/src/routes || echo "✅ no bad Query/Annotated usages"

### Step 3

Here’s a tight validation pass to confirm everything end-to-end and quickly isolate any lingering issues if OpenAPI still errors.

Quick validation (should pass)
# 1) Service up + listening
ss -lntp | grep ':4010 ' || echo '⚠️ not listening'

# 2) Health
curl -fsS http://127.0.0.1:4010/healthz | jq .

# 3) OpenAPI paths list
curl -fsS http://127.0.0.1:4010/openapi.json | jq -r '.paths | keys[]' | sort


You should see entries including:

/v1/rag/search
/v1/rag/upsert
/v1/rag/delete/by_ids
/v1/rag/delete/by_namespace
/v1/rag/delete/by_filter
/v1/rag/document
/v1/rag/upsert_markdown
/v1/rag/upsert_pdf

Smoke tests
# delete/by_ids – should 401 without admin
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -d '{"ids":["abc"]}' \
  http://127.0.0.1:4010/v1/rag/delete/by_ids

# delete/by_ids – 200 with admin (no-op ok)
curl -fsS -X POST \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: $ADMIN_KEY" \
  -d '{"ids":["abc"]}' \
  http://127.0.0.1:4010/v1/rag/delete/by_ids | jq .

# markdown loader – 200 with admin
curl -fsS -X POST "http://127.0.0.1:4010/v1/rag/upsert_markdown" \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: $ADMIN_KEY" \
  -d '{"text":"# Test\n\nhello **world**","namespace":"docs:test"}' | jq .

If /openapi.json still 500s, pinpoint the culprit fast

This runs OpenAPI generation inside Python so you see exactly which route/model blows up:

cd /opt/HX-Infrastructure-/api-gateway/gateway
./venv/bin/python - <<'PY'
from gateway.src.app import build_app
app = build_app()
o = app.openapi()
print("\n".join(sorted(o["paths"].keys())))
PY


If that throws, the traceback will name the exact route or model. Usual suspects (we’ve already addressed most of these):

Any file in gateway/src/routes/ still has from __future__ import annotations at the top.

Any POST route taking a complex request model still accidentally uses Query(...) or Annotated[..., Query(...)] instead of Body(...).

Missing Body import in a file where you used Body(...).

Handy greps (expect no output, except the ✅ lines):

grep -RIn "from __future__ import annotations" gateway/src/routes || echo "✅ no postponed annotations in routes"
grep -RInE 'Annotated\[.*Request|Query\(' gateway/src/routes || echo "✅ no bad Query/Annotated usages"

Optional cleanups (safe, not mandatory)

In rag_delete.py, the model_rebuild() calls are harmless; you can keep them or remove them now that forward refs aren’t used in routes.

Keep Query(...) only for simple scalars pulled from the query string (your DELETE /v1/rag/document?id=... is perfect).

You should be good to go. If anything still misbehaves, run the Python OpenAPI snippet above—the traceback will point straight at the remaining line to fix.