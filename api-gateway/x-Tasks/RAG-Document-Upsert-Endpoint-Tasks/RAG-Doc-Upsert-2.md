 restructuring the code to follow SOLID principles by separating models, helpers, and route logic into distinct modules is the correct approach. It improves maintainability, reduces complexity, and aligns perfectly with our established engineering standards.

Here is the refined, end-to-end implementation plan that incorporates this improved, SOLID-compliant structure.

Refined Implementation Plan: SOLID-compliant RAG Upsert Endpoint
Purpose: This plan details the deployment of the /v1/rag/upsert endpoint, ensuring the underlying code is structured according to SOLID principles for long-term maintainability.

Step 1: Create the RAG Upsert Code Modules
This phase creates the necessary Python files, separating concerns into models, services (helpers), and the route itself.

1.1 Create Pydantic Models File
Task: Create a dedicated file for the Pydantic data models used by the upsert endpoint.

Commands:

Bash

# Ensure the models directory exists
sudo mkdir -p gateway/src/models
sudo touch gateway/src/models/__init__.py

# Write the models file
sudo tee gateway/src/models/rag_upsert_models.py >/dev/null <<'PY'
from __future__ import annotations
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field

class UpsertDoc(BaseModel):
    id: Optional[str] = Field(default=None, description="Stable ID; if omitted we hash(namespace+text)")
    text: Optional[str] = Field(default=None, description="Raw text to embed (if vector not provided)")
    vector: Optional[List[float]] = Field(default=None, description="Embedding vector (skip embedding)")
    namespace: Optional[str] = Field(default=None, description="Logical grouping")
    metadata: Optional[Dict[str, Any]] = Field(default=None, description="Arbitrary payload metadata")

class UpsertRequest(BaseModel):
    documents: List[UpsertDoc] = Field(..., min_length=1, max_length=1000, description="Docs to upsert (<=1000/batch)")
    batch_size: int = Field(default=128, ge=1, le=1000)

class UpsertResponse(BaseModel):
    status: str
    upserted: int
    failed: int
    details: List[Dict[str, Any]]
PY
Validation:

Bash

# Verify the file was created and is not empty
test -s gateway/src/models/rag_upsert_models.py && echo "✅ Models file created."
1.2 Create Helper Services File
Task: Create a dedicated file for the helper functions (embedding, Qdrant client, etc.) that encapsulate external interactions.

Commands:

Bash

# Ensure the services directory exists
sudo mkdir -p gateway/src/services
sudo touch gateway/src/services/__init__.py

# Write the services/helpers file
sudo tee gateway/src/services/rag_upsert_helpers.py >/dev/null <<'PY'
from __future__ import annotations
import os
import hashlib
from typing import Any, Dict, List, Optional, Sequence, Tuple
import httpx
from fastapi import HTTPException

# ---- Env / Defaults ----
GATEWAY_BASE       = os.environ.get("GATEWAY_BASE", "http://127.0.0.1:4000").rstrip("/")
QDRANT_URL         = os.environ.get("QDRANT_URL", "http://192.168.10.30:6333").rstrip("/")
QDRANT_COLLECTION  = os.environ.get("QDRANT_COLLECTION", "hx_rag_default")
EMBEDDING_MODEL    = os.environ.get("EMBEDDING_MODEL", "emb-premium")
EMBEDDING_FALLBACK = os.environ.get("EMBEDDING_AUTH_HEADER")
LITELLM_PROXY_AUTH = os.environ.get("LITELLM_PROXY_AUTH")

# ---- Helper Functions ----
def hash_id(ns: Optional[str], text: str) -> str:
    base = f"{ns or ''}::{text}".encode("utf-8")
    return hashlib.sha256(base).hexdigest()[:32]

def auth_headers(caller_auth: Optional[str]) -> Dict[str, str]:
    headers = {"Content-Type": "application/json"}
    if caller_auth:
        headers["Authorization"] = caller_auth
    elif EMBEDDING_FALLBACK:
        headers["Authorization"] = EMBEDDING_FALLBACK
    if LITELLM_PROXY_AUTH:
        headers["X-LLM-Proxy-Authorization"] = LITELLM_PROXY_AUTH
    return headers

async def embed_texts(texts: Sequence[str], headers: Dict[str, str]) -> List[List[float]]:
    if ("Authorization" not in headers) and ("X-LLM-Proxy-Authorization" not in headers):
        raise HTTPException(401, "Authorization required to compute embeddings.")
    payload = {"model": EMBEDDING_MODEL, "input": list(texts)}
    async with httpx.AsyncClient(timeout=60.0) as client:
        r = await client.post(f"{GATEWAY_BASE}/v1/embeddings", headers=headers, json=payload)
    if r.status_code != 200:
        raise HTTPException(r.status_code, f"Embeddings error: {r.text}")
    try:
        return [row["embedding"] for row in r.json()["data"]]
    except Exception:
        raise HTTPException(500, "Unexpected embedding response format.")

async def qdrant_upsert(points: List[Dict[str, Any]]) -> Tuple[bool, str]:
    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points"
    async with httpx.AsyncClient(timeout=30.0) as client:
        r = await client.put(url, json={"points": points})
    return r.status_code == 200, r.text
PY
Validation:

Bash

# Verify the file was created and is not empty
test -s gateway/src/services/rag_upsert_helpers.py && echo "✅ Helpers file created."
1.3 Create the Upsert Route File
Task: Create the main route file, which will now be much cleaner as it imports and orchestrates the models and helpers.

Commands:

Bash

# Ensure the routes directory exists
sudo mkdir -p gateway/src/routes
sudo touch gateway/src/routes/__init__.py

# Write the route file
sudo tee gateway/src/routes/rag_upsert.py >/dev/null <<'PY'
from __future__ import annotations
from typing import Any, Dict, List, Optional
from fastapi import APIRouter, HTTPException, Request

# Import from our new SOLID-compliant modules
from ..models.rag_upsert_models import UpsertRequest, UpsertResponse
from ..services.rag_upsert_helpers import (
    auth_headers,
    embed_texts,
    hash_id,
    qdrant_upsert,
)

router = APIRouter(tags=["rag"])

@router.post("/v1/rag/upsert", response_model=UpsertResponse)
async def rag_upsert(req: UpsertRequest, request: Request) -> UpsertResponse:
    headers = auth_headers(request.headers.get("authorization"))
    docs, batch_size = req.documents, req.batch_size
    upserted, failed = 0, 0
    details: List[Dict[str, Any]] = []

    for i in range(0, len(docs), batch_size):
        chunk = docs[i : i + batch_size]
        chunk_start_index = i
        
        texts_to_embed, embed_indices = [], []
        final_vectors: List[Optional[List[float]]] = [None] * len(chunk)

        for idx, doc in enumerate(chunk):
            if doc.vector:
                final_vectors[idx] = doc.vector
            elif doc.text:
                texts_to_embed.append(doc.text)
                embed_indices.append(idx)
            else:
                failed += 1
                details.append({"index": chunk_start_index + idx, "error": "Provide text or vector"})

        if texts_to_embed:
            try:
                embedded_vectors = await embed_texts(texts_to_embed, headers)
                for i, original_idx in enumerate(embed_indices):
                    final_vectors[original_idx] = embedded_vectors[i]
            except HTTPException as e:
                for original_idx in embed_indices:
                    failed += 1
                    details.append({"index": chunk_start_index + original_idx, "error": f"Embedding failed: {e.detail}"})
        
        points_to_upsert: List[Dict[str, Any]] = []
        for idx, doc in enumerate(chunk):
            vector = final_vectors[idx]
            if not vector:
                continue
            
            point_id = doc.id or hash_id(doc.namespace, doc.text or "")
            payload = (doc.metadata or {})
            if doc.namespace:
                payload["namespace"] = doc.namespace
            
            points_to_upsert.append({"id": point_id, "vector": vector, "payload": payload})

        if not points_to_upsert:
            continue

        ok, msg = await qdrant_upsert(points_to_upsert)
        if ok:
            upserted += len(points_to_upsert)
            details.append({"batch_start": chunk_start_index, "result": f"upserted {len(points_to_upsert)}"})
        else:
            failed += len(points_to_upsert)
            details.append({"batch_start": chunk_start_index, "error": f"Qdrant upsert error: {msg[:300]}"})
            
    return UpsertResponse(status="ok", upserted=upserted, failed=failed, details=details)
PY
Validation:

Bash

# Perform a static analysis check to catch syntax or import errors
python -m pyflakes gateway/src/routes/rag_upsert.py || true
Step 2: Register the New Router
This step idempotently modifies the main application factory (app.py) to include the new upsert router.

Task:

Bash

# Add the import statement for the new router if it's not already present
grep -q "routes.rag_upsert" gateway/src/app.py || \
  sed -i '1,12 s|from \.routes\.rag import router as rag_router|from .routes.rag import router as rag_router\nfrom .routes.rag_upsert import router as rag_upsert_router|' gateway/src/app.py

# Include the new router in the FastAPI app if it's not already present
grep -q "rag_upsert_router" gateway/src/app.py || \
  sed -i 's/app\.include_router(rag_router, tags=\["rag"\])/app.include_router(rag_upsert_router, tags=["rag"])\n    app.include_router(rag_router, tags=["rag"])/' gateway/src/app.py
Validation:

Bash

# Confirm that the new router is now referenced in the main app file
grep "rag_upsert_router" gateway/src/app.py && echo "✅ Router registration present."
Step 3: Restart the Gateway Service
Apply all code changes by restarting the systemd service.

Task:

Bash

# Restart the service and wait 5 seconds
sudo systemctl restart hx-gateway-ml.service && sleep 5
Validation:

Bash

# Check the service status to confirm a successful start
systemctl --no-pager --full status hx-gateway-ml.service | sed -n '1,15p' && \
  echo "✅ HX Gateway restarted successfully!"
Step 4: Validate API Exposure
Verify that the new /v1/rag/upsert route is active and discoverable via the OpenAPI specification.

Task & Validation:

Bash

# Check the OpenAPI JSON output for the presence of the new route
curl -s http://127.0.0.1:4010/openapi.json | jq -r '.paths | keys[]' | grep '/v1/rag/upsert' && echo "✅ Upsert route present."
Step 5: Functional Smoke Test
Perform an end-to-end test by ingesting a document and then immediately querying it back via the search endpoint.

Task & Validation:

Bash

# --- 5.1 Upsert a single document ---
echo "--- Testing document upsert ---"
cat >/tmp/upsert_one.json <<'JSON'
{
  "documents": [
    {
      "text": "Citadel is Hana-X's internal AI OS used for orchestrating LLM and RAG workloads.",
      "namespace": "docs:test",
      "metadata": {"source":"inline","title":"Citadel blurb"}
    }
  ]
}
JSON

# Execute the upsert request and check for a 200 OK response
curl -i -sS -X POST "http://127.0.0.1:4010/v1/rag/upsert" \
  -H "Content-Type: application/json" \
  -d @/tmp/upsert_one.json

# --- 5.2 Query the document back ---
echo -e "\n--- Verifying upsert by querying the document back ---"
curl -sS -X POST "http://127.0.0.1:4010/v1/rag/search" \
  -H "Content-Type: application/json" \
  -d '{"query":"What is Citadel at Hana-X?","limit":3,"namespace":"docs:test"}' | jq .
Pass Criteria: The first curl must return an HTTP/1.1 200 OK. The second curl must return a JSON object with status: "ok" and at least one search result.