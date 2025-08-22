4) Restart service (+ 5s wait) and validate
sudo systemctl restart hx-gateway-ml.service && sleep 5 && echo "HX Gateway restarted successfully!"
systemctl --no-pager --full status hx-gateway-ml.service | sed -n '1,20p'

# Routes should now show new endpoints
curl -s http://127.0.0.1:4010/openapi.json | jq -r '.paths | keys[]' | sort


Expected to include:

/v1/rag/delete/by_filter
/v1/rag/delete/by_ids
/v1/rag/delete/by_namespace
/v1/rag/document
/v1/rag/upsert_markdown
/v1/rag/upsert_pdf
/metrics

5) Functional tests
5.1 Markdown upsert → search
BASE="http://127.0.0.1:4010"
ADMIN_KEY="sk-hx-admin-dev-2024"
AUTH="Bearer sk-hx-dev-1234"
NS="docs:test"

cat >/tmp/md.json <<JSON
{
  "text": "# Citadel\nCitadel is Hana-X's internal AI OS for orchestrating LLM and RAG workloads.\n\n## Features\n- Orchestration\n- RAG\n- Observability",
  "namespace": "$NS",
  "metadata": {"source":"md","title":"Citadel Readme"},
  "chunk_chars": 800,
  "overlap": 100
}
JSON

curl -sS -X POST "$BASE/v1/rag/upsert_markdown" \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: $ADMIN_KEY" \
  -d @/tmp/md.json | jq .

curl -sS -X POST "$BASE/v1/rag/search" \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"What is Citadel?\",\"limit\":3,\"namespace\":\"$NS\"}" | jq .

5.2 PDF upsert (multipart) → search
# Use any local PDF at /tmp/sample.pdf; if none, create a tiny PDF placeholder:
python3 - <<'PY'
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import letter
c = canvas.Canvas("/tmp/sample.pdf", pagesize=letter)
c.drawString(72, 720, "Citadel is Hana-X's internal AI OS for orchestrating LLM and RAG workloads.")
c.save()
PY

curl -sS -X POST "$BASE/v1/rag/upsert_pdf" \
  -H "X-HX-Admin-Key: $ADMIN_KEY" \
  -F "namespace=$NS" \
  -F "chunk_chars=1200" \
  -F "overlap=100" \
  -F 'metadata_json={"source":"pdf","title":"Citadel PDF"}' \
  -F "file=@/tmp/sample.pdf" | jq .

curl -sS -X POST "$BASE/v1/rag/search" \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"RAG workloads\",\"limit\":3,\"namespace\":\"$NS\"}" | jq .

5.3 Delete by namespace
curl -sS -X POST "$BASE/v1/rag/delete/by_namespace" \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: $ADMIN_KEY" \
  -d "{\"namespace\":\"$NS\"}" | jq .

# Verify count = 0
QDRANT_URL="${QDRANT_URL:-http://192.168.10.30:6333}"
COLL="${QDRANT_COLLECTION:-hx_rag_default}"
curl -sS -X POST "$QDRANT_URL/collections/$COLL/points/count" \
  -H "Content-Type: application/json" \
  -d "{\"exact\":true,\"filter\":{\"must\":[{\"key\":\"namespace\",\"match\":{\"value\":\"$NS\"}}]}}" | jq .

5.4 Metrics check
curl -s http://127.0.0.1:4010/metrics | head -40
# expect counters like:
# rag_upserts_total{result="ok"} ...
# rag_search_total{result="ok",path="/v1/rag/search"} ...

6) Makefile add-ons (optional, handy)
.PHONY: rag-delete-ns rag-upsert-md rag-upsert-pdf metrics
rag-delete-ns:
	@curl -sS -X POST "$(BASE)/v1/rag/delete/by_namespace" \
	  -H "Content-Type: application/json" \
	  -H "X-HX-Admin-Key: $(ADMIN_KEY)" \
	  -d '{"namespace":"$(NS)"}' | jq .

rag-upsert-md:
	@printf '%s\n' '{ "text": "# Title\nBody text here.", "namespace": "'$(NS)'", "metadata": {"source":"make"} }' > /tmp/md.json
	@curl -sS -X POST "$(BASE)/v1/rag/upsert_markdown" \
	  -H "Content-Type: application/json" \
	  -H "X-HX-Admin-Key: $(ADMIN_KEY)" \
	  -d @/tmp/md.json | jq .

rag-upsert-pdf:
	@curl -sS -X POST "$(BASE)/v1/rag/upsert_pdf" \
	  -H "X-HX-Admin-Key: $(ADMIN_KEY)" \
	  -F "namespace=$(NS)" \
	  -F "chunk_chars=1200" \
	  -F "overlap=100" \
	  -F 'metadata_json={"source":"pdf","title":"Makefile PDF"}' \
	  -F "file=@/tmp/sample.pdf" | jq .

metrics:
	@curl -s $(BASE)/metrics | head -40

Validation Requirement (per HX standards)

After each code change, restart the service and validate:

Port 4010 listening,

/healthz OK,

New routes present in /openapi.json,

Smoke test upsert/search/delete,

/metrics returns Prometheus text output.