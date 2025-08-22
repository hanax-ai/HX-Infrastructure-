1) Smoke tests (copy–paste friendly)
BASE="http://127.0.0.1:4010"
ADMIN_KEY="sk-hx-admin-dev-2024"        # write-scope (X-HX-Admin-Key)
AUTH="Bearer sk-hx-dev-1234"            # LiteLLM proxy key (for embeddings)
NS="docs:test"
QDRANT_URL="${QDRANT_URL:-http://192.168.10.30:6333}"
COLL="${QDRANT_COLLECTION:-hx_rag_default}"

echo "== Health ==" && curl -s "$BASE/healthz" | jq .

echo "== Routes ==" && curl -s "$BASE/openapi.json" | jq -r '.paths | keys[]' | sort

1A) Upsert (text → auto-embed) → expect 200 OK
cat >/tmp/upsert_one.json <<JSON
{
  "documents": [
    {
      "text": "Citadel is Hana-X's internal AI OS used for orchestrating LLM and RAG workloads.",
      "namespace": "$NS",
      "metadata": {"source":"smoke","title":"Citadel blurb"}
    }
  ]
}
JSON

curl -i -sS -X POST "$BASE/v1/rag/upsert" \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: $ADMIN_KEY" \
  -H "Authorization: $AUTH" \
  -d @/tmp/upsert_one.json | sed -n '1,20p'

1B) Query it back (query → embed with fallback) → expect 200 and "status":"ok"
curl -sS -X POST "$BASE/v1/rag/search" \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"What is Citadel at Hana-X?\",\"limit\":3,\"namespace\":\"$NS\"}" | jq .

1C) Vector-path search (no auth, no embed) – use correct dimension 1024
python3 - <<'PY' >/tmp/vec1024.json
import json; print(json.dumps({"vector":[0.0]*1024,"limit":3}))
PY

curl -sS -X POST "$BASE/v1/rag/search" \
  -H "Content-Type: application/json" \
  -d @/tmp/vec1024.json | jq .

1D) Dimension guard (negative test) – expect 4xx with message
cat >/tmp/bad_vec.json <<'JSON'
{"documents":[{"namespace":"test","vector":[1.0,2.0,3.0],"metadata":{"test":"bad-vector"}}]}
JSON

curl -i -sS -X POST "$BASE/v1/rag/upsert" \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: $ADMIN_KEY" \
  -d @/tmp/bad_vec.json | sed -n '1,25p'

1E) Idempotency (same text twice) – should not create dupes
curl -sS -X POST "$BASE/v1/rag/upsert" \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: $ADMIN_KEY" \
  -H "Authorization: $AUTH" \
  -d @/tmp/upsert_one.json | jq .

# Count points for the namespace (Qdrant)
curl -sS -X POST "$QDRANT_URL/collections/$COLL/points/count" \
  -H "Content-Type: application/json" \
  -d "{\"exact\":true,\"filter\":{\"must\":[{\"key\":\"namespace\",\"match\":{\"value\":\"$NS\"}}]}}" | jq .

1F) Namespace isolation (should return 0 results)
curl -sS -X POST "$BASE/v1/rag/search" \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"Citadel\",\"limit\":3,\"namespace\":\"docs:other\"}" | jq .

2) Handy make targets (drop-in)

Append these to your repo Makefile (idempotent content — adjust paths if your tree differs):

BASE?=http://127.0.0.1:4010
ADMIN_KEY?=sk-hx-admin-dev-2024
AUTH?=Bearer sk-hx-dev-1234
NS?=docs:test
QDRANT_URL?=http://192.168.10.30:6333
COLL?=hx_rag_default

.PHONY: gateway-start gateway-stop gateway-restart gateway-status gateway-logs openapi
gateway-start:
	@sudo systemctl start hx-gateway-ml.service && sleep 5 && echo "HX Gateway started successfully!"

gateway-stop:
	@sudo systemctl stop hx-gateway-ml.service && sleep 5 && echo "HX Gateway stopped successfully!"

gateway-restart:
	@sudo systemctl restart hx-gateway-ml.service && sleep 5 && echo "HX Gateway restarted successfully!"

gateway-status:
	@systemctl --no-pager --full status hx-gateway-ml.service | sed -n '1,20p'

gateway-logs:
	@sudo journalctl -xeu hx-gateway-ml.service --no-pager -n 80 | tail -n 80

openapi:
	@curl -s $(BASE)/openapi.json | jq -r '.paths | keys[]' | sort

.PHONY: rag-upsert-one rag-search rag-search-vec rag-bad-upsert qdrant-count qdrant-clear-ns
rag-upsert-one:
	@printf '%s\n' '{ "documents": [ { "text": "Citadel is Hana-X''s internal AI OS used for orchestrating LLM and RAG workloads.", "namespace": "'$(NS)'", "metadata": {"source":"make","title":"Citadel blurb"} } ] }' > /tmp/upsert_one.json
	@curl -i -sS -X POST "$(BASE)/v1/rag/upsert" \
	  -H "Content-Type: application/json" \
	  -H "X-HX-Admin-Key: $(ADMIN_KEY)" \
	  -H "Authorization: $(AUTH)" \
	  -d @/tmp/upsert_one.json | sed -n '1,20p'

rag-search:
	@curl -sS -X POST "$(BASE)/v1/rag/search" \
	  -H "Content-Type: application/json" \
	  -d '{"query":"What is Citadel at Hana-X?","limit":3,"namespace":"$(NS)"}' | jq .

rag-search-vec:
	@python3 - <<'PY' >/tmp/vec1024.json
import json; print(json.dumps({"vector":[0.0]*1024,"limit":3}))
PY
	@curl -sS -X POST "$(BASE)/v1/rag/search" \
	  -H "Content-Type: application/json" \
	  -d @/tmp/vec1024.json | jq .

rag-bad-upsert:
	@printf '%s\n' '{"documents":[{"namespace":"test","vector":[1.0,2.0,3.0],"metadata":{"test":"bad-vector"}}]}' > /tmp/bad_vec.json
	@curl -i -sS -X POST "$(BASE)/v1/rag/upsert" \
	  -H "Content-Type: application/json" \
	  -H "X-HX-Admin-Key: $(ADMIN_KEY)" \
	  -d @/tmp/bad_vec.json | sed -n '1,25p'

qdrant-count:
	@curl -sS -X POST "$(QDRANT_URL)/collections/$(COLL)/points/count" \
	  -H "Content-Type: application/json" \
	  -d '{"exact":true,"filter":{"must":[{"key":"namespace","match":{"value":"$(NS)"}}]}}' | jq .

qdrant-clear-ns:
	@curl -sS -X POST "$(QDRANT_URL)/collections/$(COLL)/points/delete" \
	  -H "Content-Type: application/json" \
	  -d '{"filter":{"must":[{"key":"namespace","match":{"value":"$(NS)"}}]}}' | jq .


Each service command includes a 5-second wait and a success message, per the HX service management standard.

3) Quick acceptance checklist

 /healthz returns {"ok": true}

 /openapi.json lists /v1/rag/upsert and /v1/rag/search

 Upsert (text) returns 200 OK

 Search (query) returns status:"ok" (0+ results; ≥1 after upsert)

 Upsert dimension guard rejects vectors not 1024 long

 Re-upsert same text does not create duplicates (count unchanged)

 Namespace filter isolates results as expected

If anything fails, run:

make gateway-logs


and drop the last 30–50 lines; I’ll zero in fast.