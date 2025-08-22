2) Markdown/PDF loader → chunks → upsert
2.1 Services: simple chunker + loaders
sudo tee gateway/src/services/document_loader.py >/dev/null <<'PY'
from __future__ import annotations
from typing import List, Dict, Any, Optional
from pydantic import BaseModel
from ..models.rag_upsert_models import UpsertDoc

def _chunk_text(text: str, chunk_chars: int = 1500, overlap: int = 200) -> List[str]:
    text = text or ""
    if chunk_chars <= 0:
        return [text]
    chunks = []
    start = 0
    n = len(text)
    while start < n:
        end = min(n, start + chunk_chars)
        chunks.append(text[start:end])
        if end == n:
            break
        start = max(0, end - overlap)
    return chunks

def load_markdown(md_text: str, namespace: str, metadata: Optional[Dict[str, Any]] = None,
                  chunk_chars: int = 1500, overlap: int = 200) -> List[UpsertDoc]:
    # For now, treat markdown as plain text; headings/content preserved literally.
    chunks = _chunk_text(md_text, chunk_chars, overlap)
    docs = []
    for i, ch in enumerate(chunks):
        meta = dict(metadata or {})
        meta.update({"chunk_index": i, "format": "md"})
        docs.append(UpsertDoc(text=ch, namespace=namespace, metadata=meta))
    return docs

def load_pdf_bytes(pdf_bytes: bytes, namespace: str, metadata: Optional[Dict[str, Any]] = None,
                   chunk_chars: int = 1500, overlap: int = 200) -> List[UpsertDoc]:
    from pypdf import PdfReader
    import io
    pdf = PdfReader(io.BytesIO(pdf_bytes))
    full_text = []
    for page in pdf.pages:
        try:
            full_text.append(page.extract_text() or "")
        except Exception:
            full_text.append("")
    text = "\n".join(full_text)
    chunks = _chunk_text(text, chunk_chars, overlap)
    docs = []
    for i, ch in enumerate(chunks):
        meta = dict(metadata or {})
        meta.update({"chunk_index": i, "format": "pdf"})
        docs.append(UpsertDoc(text=ch, namespace=namespace, metadata=meta))
    return docs
PY

2.2 Routes: upsert endpoints for markdown and PDF
sudo tee gateway/src/routes/rag_loader.py >/dev/null <<'PY'
from __future__ import annotations
from typing import Optional, Dict, Any, List
from fastapi import APIRouter, UploadFile, File, Form, HTTPException, Depends
from pydantic import BaseModel, Field

from .security import require_rag_write
from ..services.document_loader import load_markdown, load_pdf_bytes
from ..services.rag_upsert_helpers import auth_headers, embed_texts, qdrant_upsert, hash_id
from ..models.rag_upsert_models import UpsertResponse, UpsertDoc

router = APIRouter(tags=["rag"])

class MarkdownUpsertRequest(BaseModel):
    text: str = Field(..., min_length=1)
    namespace: str = Field(..., min_length=1)
    metadata: Optional[Dict[str, Any]] = None
    chunk_chars: int = Field(default=1500, ge=256, le=8000)
    overlap: int = Field(default=200, ge=0, le=2000)
    batch_size: int = Field(default=128, ge=1, le=1000)

@router.post("/v1/rag/upsert_markdown", response_model=UpsertResponse, dependencies=[Depends(require_rag_write)])
async def upsert_markdown(req: MarkdownUpsertRequest) -> UpsertResponse:
    docs = load_markdown(req.text, req.namespace, req.metadata, req.chunk_chars, req.overlap)
    # Reuse the existing upsert path: embed where needed and push to Qdrant
    upserted, failed, details = 0, 0, []
    # Prepare for embedding
    texts = [d.text or "" for d in docs]
    headers = auth_headers(None)  # fallback EMBEDDING_AUTH_HEADER if configured
    try:
        vectors = await embed_texts(texts, headers)
    except HTTPException as e:
        raise
    # Build points
    points = []
    for i, d in enumerate(docs):
        v = vectors[i]
        pid = d.id or hash_id(d.namespace, d.text or "")
        payload = dict(d.metadata or {})
        if d.namespace:
            payload["namespace"] = d.namespace
        points.append({"id": pid, "vector": v, "payload": payload})
    # Upsert in one go (or chunk if preferred)
    ok, msg = await qdrant_upsert(points)
    if ok:
        upserted = len(points)
        details.append({"result": f"upserted {len(points)}"})
    else:
        failed = len(points)
        details.append({"error": f"Qdrant upsert error: {msg[:300]}"})
    return UpsertResponse(status="ok", upserted=upserted, failed=failed, details=details)

@router.post("/v1/rag/upsert_pdf", response_model=UpsertResponse, dependencies=[Depends(require_rag_write)])
async def upsert_pdf(
    namespace: str = Form(...),
    metadata_json: Optional[str] = Form(None),
    chunk_chars: int = Form(1500),
    overlap: int = Form(200),
    file: UploadFile = File(...)
) -> UpsertResponse:
    import json
    metadata = None
    if metadata_json:
        try:
            metadata = json.loads(metadata_json)
        except Exception as e:
            raise HTTPException(400, f"Invalid metadata_json: {e}")
    pdf_bytes = await file.read()
    docs = load_pdf_bytes(pdf_bytes, namespace, metadata, chunk_chars, overlap)

    # Embed + upsert
    texts = [d.text or "" for d in docs]
    headers = auth_headers(None)
    try:
        vectors = await embed_texts(texts, headers)
    except HTTPException as e:
        raise
    points = []
    for i, d in enumerate(docs):
        v = vectors[i]
        pid = d.id or hash_id(d.namespace, d.text or "")
        payload = dict(d.metadata or {})
        if d.namespace:
            payload["namespace"] = d.namespace
        points.append({"id": pid, "vector": v, "payload": payload})
    ok, msg = await qdrant_upsert(points)
    if not ok:
        raise HTTPException(502, f"Qdrant upsert error: {msg[:300]}")
    return UpsertResponse(status="ok", upserted=len(points), failed=0, details=[{"result": f"upserted {len(points)}"}])
PY