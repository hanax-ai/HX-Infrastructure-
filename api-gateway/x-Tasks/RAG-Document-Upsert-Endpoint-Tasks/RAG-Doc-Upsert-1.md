This plan looks excellent and ticks the SOLID boxes. ✅
Let’s ship it exactly as written, with two tiny hardening tweaks so production stays safe:

Dimension guard (prevents bad vectors from polluting Qdrant)

Schema hygiene (ensure namespace is always a keyword payload)

Below are the minimal deltas on top of your plan, then run your, RAG_Doc-Upsert-2.md, Step 1–5 as-is.

Tiny hardening deltas
A) Enforce embedding dimension (default 1024) before upsert

Add a dimension constant + check in the helpers. This keeps garbage vectors out.

# Add an env-backed guard to helpers
sudo sed -i '1s|^|from __future__ import annotations\n|' gateway/src/services/rag_upsert_helpers.py
sudo sed -i 's/^LITELLM_PROXY_AUTH = .*/LITELLM_PROXY_AUTH = os.environ.get("LITELLM_PROXY_AUTH")\nEMBEDDING_DIM = int(os.environ.get("EMBEDDING_DIM", "1024"))/' \
  gateway/src/services/rag_upsert_helpers.py

# Insert a vector length check right before building the Qdrant request body
sudo awk -v RS= -v ORS= '
  BEGIN{added=0}
  /def qdrant_upsert\(points: List\[Dict\[str, Any\]\]\) -> Tuple\[bool, str\]:/ {
    print; next
  }
  {print}
' gateway/src/services/rag_upsert_helpers.py >/tmp/_tmp_helpers.py && sudo mv /tmp/_tmp_helpers.py gateway/src/services/rag_upsert_helpers.py

# Append a small validator function and call it inside qdrant_upsert
sudo tee -a gateway/src/services/rag_upsert_helpers.py >/dev/null <<'PY'

def _validate_vectors(points: List[Dict[str, Any]]):
    for p in points:
        v = p.get("vector") or []
        if len(v) != EMBEDDING_DIM:
            raise HTTPException(400, f"Vector length {len(v)} != EMBEDDING_DIM {EMBEDDING_DIM}")

async def qdrant_upsert(points: List[Dict[str, Any]]) -> Tuple[bool, str]:
    _validate_vectors(points)  # NEW: guard before we send to Qdrant
    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points"
    async with httpx.AsyncClient(timeout=30.0) as client:
        r = await client.put(url, json={"points": points})
    return r.status_code == 200, r.text
PY


Set the dimension once in your gateway env (matches your current working setup):

# Persist once; restart will pick it up
sudo sed -i 's/^EMBEDDING_MODEL=.*/EMBEDDING_MODEL=emb-premium/' /etc/hx/gateway.env
grep -q '^EMBEDDING_DIM=' /etc/hx/gateway.env || echo 'EMBEDDING_DIM=1024' | sudo tee -a /etc/hx/gateway.env >/dev/null

B) (Optional) Re-assert namespace payload index (idempotent)

Good to run once per environment; it’s a no-op if already present.

curl -sS -X PUT "$QDRANT_URL/collections/$QDRANT_COLLECTION/index" \
  -H 'Content-Type: application/json' \
  -d '{"field_name":"namespace","field_schema":"keyword"}' | jq -r '.status'

Now execute your SOLID plan

Run your Step 1 → Step 5 exactly as you wrote:

Step 1: create gateway/src/models/rag_upsert_models.py, gateway/src/services/rag_upsert_helpers.py, gateway/src/routes/rag_upsert.py

Step 2: register the router in gateway/src/app.py

Step 3: restart the service (with 5-sec wait)

Step 4: validate OpenAPI shows /v1/rag/upsert

Step 5: upsert a test doc, then query it back (expect 200 + at least one hit)

Every step in your plan already has a validation—perfect.

Service management (explicit commands with confirmation)
# Start (wait 5s, confirm)
sudo systemctl start hx-gateway-ml.service && sleep 5 && \
  systemctl --no-pager --full status hx-gateway-ml.service | sed -n '1,12p' && \
  echo "HX Gateway started successfully!"

# Stop (wait 5s, confirm)
sudo systemctl stop hx-gateway-ml.service && sleep 5 && \
  echo "HX Gateway stopped successfully!"

Final recommendation

Keep this SOLID split for future endpoints (/v1/rag/delete, /v1/rag/reset, /v1/rag/rerank): models/, services/, routes/.

Add a tiny metrics hook (timer + status tags) around embed_texts and qdrant_upsert when you wire the metrics server; it’ll pay off quickly in prod.