Here are the surgical tweaks I’d make to make it rock-solid, safer, and a tad more self-validating:

High-impact nits

Add a default goal + a PORT var and health checks

Gives make a friendly landing page and lets service targets validate themselves.

Harden all curl calls with -fsS

Fails on HTTP ≥ 400 and honors pipefail, so broken calls don’t silently “succeed”.

Fix Qdrant index endpoints + verification

Use the canonical PUT /collections/<coll>/index (not /index/<field>), and verify via payload_schema.

Avoid hardcoding secrets in the Makefile defaults

Keep the variables but default them to blanks; let operators set them via env or a .env include.

Add quick “require tools” guard

Early, clear error if curl/jq/ss aren’t present.

Minimal patch (drop-in)

Paste/merge these changes:

Header & defaults
# Default goal + stricter shell
.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
.SHELLFLAGS := -eo pipefail -c

# Tools guard (optional, but helpful)
REQUIRE_TOOLS := curl jq ss
require-tools:
	@for t in $(REQUIRE_TOOLS); do command -v $$t >/dev/null 2>&1 || { echo "Missing tool: $$t"; exit 1; }; done

# Conf
PORT ?= 4010
BASE ?= http://127.0.0.1:$(PORT)
ADMIN_KEY ?=
AUTH ?=
NS ?= docs:test
QDRANT_URL ?= http://192.168.10.30:6333
COLL ?= hx_rag_default
GATEWAY_DIR ?= /opt/HX-Infrastructure-/api-gateway/gateway

.PHONY: help require-tools ...

Service checks (new helpers)
.PHONY: check-health check-port check-openapi
check-health:
	@curl -fsS "$(BASE)/healthz" | jq -e '.ok == true' >/dev/null && echo "✓ Health OK" || { echo "✗ Health failed"; exit 1; }

check-port:
	@ss -lntp | grep ":$(PORT) " >/dev/null && echo "✓ Listening on :$(PORT)" || { echo "✗ Not listening on :$(PORT)"; exit 1; }

check-openapi:
	@curl -fsS "$(BASE)/openapi.json" >/dev/null && echo "✓ OpenAPI reachable" || { echo "✗ OpenAPI not reachable"; exit 1; }

Service management (add validation)
gateway-start: require-tools
	@sudo systemctl start hx-gateway-ml.service && sleep 5 && echo "→ Validating..." && $(MAKE) -s check-port check-health && echo "HX Gateway started successfully!"

gateway-stop: require-tools
	@sudo systemctl stop hx-gateway-ml.service && sleep 5 && \
	( ! ss -lntp | grep ":$(PORT) " >/dev/null ) && echo "HX Gateway stopped successfully!" || { echo "✗ Still listening on :$(PORT)"; exit 1; }

gateway-restart: require-tools
	@sudo systemctl restart hx-gateway-ml.service && sleep 5 && echo "→ Validating..." && $(MAKE) -s check-port check-health && echo "HX Gateway restarted successfully!"

Make the curls fail fast and fix Qdrant index calls

Replace your three curl -X PUT .../index/<field> calls with this:

rag-optimize: require-tools  ## Optimize Qdrant performance (indexes, etc.)
	@echo "=== Qdrant Performance Optimization ==="
	@echo "Creating/ensuring 'namespace' index..."
	@curl -fsS -X PUT "$(QDRANT_URL)/collections/$(COLL)/index" \
	  -H "Content-Type: application/json" \
	  -d '{"field_name":"namespace","field_schema":"keyword"}' | jq -r '.status'
	@echo "Creating/ensuring 'doc_id' index..."
	@curl -fsS -X PUT "$(QDRANT_URL)/collections/$(COLL)/index" \
	  -H "Content-Type: application/json" \
	  -d '{"field_name":"doc_id","field_schema":"keyword"}' | jq -r '.status'
	@echo "Creating/ensuring 'expires_at' index..."
	@curl -fsS -X PUT "$(QDRANT_URL)/collections/$(COLL)/index" \
	  -H "Content-Type: application/json" \
	  -d '{"field_name":"expires_at","field_schema":"datetime"}' | jq -r '.status'
	@echo "✓ Qdrant optimization completed"


…and verify them against payload_schema:

rag-verify-index: require-tools  ## Verify Qdrant field indexes are active
	@echo "=== Verifying Qdrant Field Indexes ==="
	@curl -fsS "$(QDRANT_URL)/collections/$(COLL)" | \
	  jq '{namespace: (.result.payload_schema | has("namespace")), doc_id: (.result.payload_schema | has("doc_id")), expires_at: (.result.payload_schema | has("expires_at"))}' | tee /dev/stderr | \
	  jq -e 'select(.namespace and .doc_id and .expires_at)' >/dev/null && echo "✓ Index verification completed" || { echo "✗ Missing one or more indexes"; exit 1; }

Harden the other HTTP calls (just add -fsS)

Example replacements:

openapi:
	@curl -fsS $(BASE)/openapi.json | jq -r '.paths | keys[]' | sort

rag-upsert-one:
	@printf '%s\n' '{ "documents": [ { "text": "Citadel is Hana-X'\''s internal AI OS used for orchestrating LLM and RAG workloads.", "namespace": "$(NS)", "metadata": {"source":"make","title":"Citadel blurb"} } ] }' > /tmp/upsert_one.json
	@curl -fsS -i -X POST "$(BASE)/v1/rag/upsert" \
	  -H "Content-Type: application/json" \
	  $(if $(ADMIN_KEY),-H "X-HX-Admin-Key: $(ADMIN_KEY)",) \
	  $(if $(AUTH),-H "Authorization: $(AUTH)",) \
	  -d @/tmp/upsert_one.json | sed -n '1,20p'

rag-search:
	@curl -fsS -X POST "$(BASE)/v1/rag/search" \
	  -H "Content-Type: application/json" \
	  -d '{"query":"What is Citadel at Hana-X?","limit":3,"namespace":"$(NS)"}' | jq .

rag-bad-upsert:
	@printf '%s\n' '{"documents":[{"namespace":"test","vector":[1.0,2.0,3.0],"metadata":{"test":"bad-vector"}}]}' > /tmp/bad_vec.json
	@curl -fsS -i -X POST "$(BASE)/v1/rag/upsert" \
	  -H "Content-Type: application/json" \
	  $(if $(ADMIN_KEY),-H "X-HX-Admin-Key: $(ADMIN_KEY)",) \
	  -d @/tmp/bad_vec.json | sed -n '1,25p'

qdrant-count:
	@curl -fsS -X POST "$(QDRANT_URL)/collections/$(COLL)/points/count" \
	  -H "Content-Type: application/json" \
	  -d '{"exact":true,"filter":{"must":[{"key":"namespace","match":{"value":"$(NS)"}}]}}' | jq .


Note the $(if $(ADMIN_KEY), ...) pattern keeps headers out if you didn’t export them—safer defaults.

Optional (nice to have)

.env include:
Add -include .env at the top and export vars there; keep secrets out of VCS.

rag-test-all orchestrator (validates as a single flow):
rag-optimize → rag-verify-index → rag-upsert-one → rag-search

TL;DR

Your Makefile is already great. The changes above make it:

safer (no silent HTTP failures),

cleaner (canonical Qdrant API usage),

more secure (no token defaults leaked),

and self-validating (health/port/OpenAPI checks baked in).