"""
RAG Document Upsert Routes

FastAPI router for RAG document upsert operations with write-scope authentication,
comprehensive error handling, and OpenAPI documentation.
"""

import os
from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException, Request

from ..models.rag_upsert_models import UpsertRequest, UpsertResponse
from ..services.rag_upsert_helpers import (
    auth_headers,
    embed_texts,
    hash_id,
    qdrant_upsert,
)
from ..services.security import get_embedding_auth_from_request, require_rag_write

router = APIRouter(tags=["rag"])

# ---- Env toggles / guardrails ------------------------------------------------
EMBEDDING_DIM = int(os.environ.get("EMBEDDING_DIM", "0"))  # 0 = disabled
TEXT_PREVIEW_CHARS = int(os.environ.get("TEXT_PREVIEW_CHARS", "200"))


@router.post(
    "/v1/rag/upsert",
    response_model=UpsertResponse,
    summary="Upsert RAG Documents",
    description="Batch upsert documents to the RAG vector database with embedding generation",
    responses={
        200: {
            "description": "Documents successfully upserted",
            "content": {
                "application/json": {
                    "example": {
                        "status": "ok",
                        "upserted": 2,
                        "failed": 0,
                        "details": [{"batch_start": 0, "result": "upserted 2"}],
                    }
                }
            },
        },
        401: {"description": "Authentication required"},
        403: {"description": "Invalid admin key"},
        422: {"description": "Validation error"},
        500: {"description": "Internal server error"},
    },
)
async def rag_upsert(
    req: UpsertRequest,
    request: Request,
    _admin_key: str = Depends(require_rag_write),  # validated; value not used directly
) -> UpsertResponse:
    """
    Upsert documents to the RAG vector database.

    Accepts either:
    - Text (auto-embedded), or
    - Pre-computed vectors (used as-is)

    Uses write-scope authentication via `X-HX-Admin-Key`.
    """
    # Build auth for embeddings (caller Authorization or service fallback)
    auth = get_embedding_auth_from_request(request)
    headers = auth_headers(auth)

    docs = req.documents
    batch_size = req.batch_size

    upserted = 0
    failed = 0
    details: list[dict[str, Any]] = []

    # Process in batches
    for i in range(0, len(docs), batch_size):
        chunk = docs[i : i + batch_size]
        chunk_start_index = i

        # Collect for embedding
        texts_to_embed: list[str] = []
        embed_indices: list[int] = []
        final_vectors: list[Optional[list[float]]] = [None] * len(chunk)

        # First pass: categorize & validate
        had_candidates = False
        for idx, doc in enumerate(chunk):
            if doc.vector is not None:
                had_candidates = True
                final_vectors[idx] = doc.vector
            elif doc.text:
                had_candidates = True
                texts_to_embed.append(doc.text)
                embed_indices.append(idx)
            else:
                failed += 1
                details.append(
                    {
                        "index": chunk_start_index + idx,
                        "error": "Document must provide either 'text' or 'vector'",
                    }
                )

        # Generate embeddings where needed
        if texts_to_embed:
            try:
                embedded_vectors = await embed_texts(texts_to_embed, headers)
                for j, original_idx in enumerate(embed_indices):
                    if j < len(embedded_vectors):
                        final_vectors[original_idx] = embedded_vectors[j]
                    else:
                        failed += 1
                        details.append(
                            {
                                "index": chunk_start_index + original_idx,
                                "error": "Embedding generation failed - missing vector",
                            }
                        )
            except HTTPException as e:
                for original_idx in embed_indices:
                    failed += 1
                    details.append(
                        {
                            "index": chunk_start_index + original_idx,
                            "error": f"Embedding failed: {e.detail}",
                        }
                    )

        # Prepare points
        points_to_upsert: list[dict[str, Any]] = []
        for idx, doc in enumerate(chunk):
            vector = final_vectors[idx]
            if not vector:
                continue

            point_id = doc.id or hash_id(doc.namespace, doc.text or "")
            payload: dict[str, Any] = doc.metadata.copy() if doc.metadata else {}
            payload["doc_id"] = point_id  # stable identifier for indexing/cleanup
            if doc.namespace:
                payload["namespace"] = doc.namespace
            if doc.text and TEXT_PREVIEW_CHARS > 0:
                preview = doc.text[:TEXT_PREVIEW_CHARS]
                if len(doc.text) > TEXT_PREVIEW_CHARS:
                    preview += "…"
                payload["text_preview"] = preview

            points_to_upsert.append(
                {"id": point_id, "vector": vector, "payload": payload}
            )

        # If nothing to upsert, annotate batch outcome only when we had candidates
        if not points_to_upsert:
            if had_candidates:
                details.append(
                    {
                        "batch_start": chunk_start_index,
                        "result": "No valid documents in batch",
                    }
                )
            continue

        # Upsert batch to Qdrant
        try:
            ok, msg = await qdrant_upsert(points_to_upsert)
            if ok:
                upserted += len(points_to_upsert)
                details.append(
                    {
                        "batch_start": chunk_start_index,
                        "result": f"Successfully upserted {len(points_to_upsert)} documents",
                    }
                )
            else:
                failed += len(points_to_upsert)
                details.append(
                    {
                        "batch_start": chunk_start_index,
                        "error": f"Qdrant upsert failed: {msg[:300]}",
                    }
                )
        except HTTPException:
            # Let HTTPException bubble up (e.g., dimension validation errors)
            raise
        except Exception as e:
            failed += len(points_to_upsert)
            details.append(
                {
                    "batch_start": chunk_start_index,
                    "error": f"Upsert exception: {str(e)[:300]}",
                }
            )

    status = "ok" if failed == 0 else ("partial" if upserted > 0 else "error")
    return UpsertResponse(
        status=status, upserted=upserted, failed=failed, details=details
    )
