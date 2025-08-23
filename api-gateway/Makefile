# HX-Infrastructure Makefile

# Optional .env include (for local secrets/overrides)
-include .env

# Default goal + stricter shell
.DEFAULT_GOAL := help
SHELL := /usr/bin/env bash
.SHELLFLAGS := -eo pipefail -c

# Tools guard (optional, but helpful)
REQUIRE_TOOLS := curl jq ss
require-tools:
	@for t in $(REQUIRE_TOOLS); do command -v $$t >/dev/null 2>&1 || { echo "Missing tool: $$t"; exit 1; }; done

.PHONY: help require-tools deps-dev test-quick openapi gateway-start gateway-stop gateway-restart gateway-status gateway-logs rag-upsert-one rag-search rag-search-vec rag-bad-upsert qdrant-count qdrant-clear-ns rag-ttl-cleanup rag-ttl-preview rag-ttl-status rag-optimize rag-verify-index check-health check-port check-openapi rag-test-all check-tools check-static lint format type-check test-contract

# Configuration variables (safer defaults - no secrets)
PORT ?= 4010
BASE ?= http://127.0.0.1:$(PORT)
ADMIN_KEY ?=
AUTH ?=
NS ?= docs:test
QDRANT_URL ?= http://192.168.10.30:6333
COLL ?= hx_rag_default
GATEWAY_DIR ?= /opt/HX-Infrastructure-/api-gateway/gateway

help:
	@echo "HX-Infrastructure Makefile"
	@echo "Targets:"
	@echo "  deps-dev         Install test/dev deps"
	@echo "  test-quick       Run pytest quickly"
	@echo "  openapi          Show API endpoints"
	@echo ""
	@echo "CI Gates (Prevent Drift):"
	@echo "  check-tools      Verify all linting tools available"
	@echo "  check-static     Run all static analysis (ruff + black + mypy)"
	@echo "  lint             Run ruff linter"
	@echo "  format           Run black formatter"
	@echo "  type-check       Run mypy type checking"
	@echo "  test-contract    Run contract tests (200/401/422 for all routes)"
	@echo ""
	@echo "Gateway Service Management:"
	@echo "  gateway-start    Start HX Gateway service"
	@echo "  gateway-stop     Stop HX Gateway service"
	@echo "  gateway-restart  Restart HX Gateway service"
	@echo "  gateway-status   Show service status"
	@echo "  gateway-logs     Show recent service logs"
	@echo ""
	@echo "RAG Testing:"
	@echo "  rag-upsert-one   Test document upsert"
	@echo "  rag-search       Test query search"
	@echo "  rag-search-vec   Test vector search"
	@echo "  rag-bad-upsert   Test dimension validation"
	@echo "  qdrant-count     Count documents in namespace"
	@echo "  qdrant-clear-ns  Clear namespace documents"
	@echo ""
	@echo "TTL Management:"
	@echo "  rag-ttl-cleanup  Run TTL cleanup to remove expired documents"
	@echo "  rag-ttl-preview  Preview what would be cleaned up (dry-run)"
	@echo "  rag-ttl-status   Check TTL cleanup logs and cron status"
	@echo ""
	@echo "Performance & Optimization:"
	@echo "  rag-optimize     Optimize Qdrant performance (indexes, etc.)"
	@echo "  rag-verify-index Verify Qdrant field indexes are active"
	@echo ""
	@echo "Service Checks:"
	@echo "  check-health     Verify service health endpoint"
	@echo "  check-port       Verify service is listening on port"
	@echo "  check-openapi    Comprehensive OpenAPI schema validation"
	@echo ""
	@echo "Orchestration:"
	@echo "  rag-test-all     Run complete RAG test flow"
	@echo "  require-tools    Check for required tools (curl, jq, ss)"

# ====================
# Service Check Helpers
# ====================

check-health:
	@curl -fsS "$(BASE)/healthz" | jq -e '.ok == true' >/dev/null && echo "✓ Health OK" || { echo "✗ Health failed"; exit 1; }

check-port:
	@ss -lntp | grep ":$(PORT) " >/dev/null && echo "✓ Listening on :$(PORT)" || { echo "✗ Not listening on :$(PORT)"; exit 1; }

check-openapi:
	@echo "🔍 Running comprehensive OpenAPI validation..."
	@./api-gateway/scripts/tests/check-openapi.sh

deps-dev:
	cd api-gateway/gateway && python -m pip install -U pytest pytest-asyncio httpx pyflakes black isort ruff mypy types-requests

test-quick:
	cd api-gateway && PYTHONPATH=. python -m pytest -q

# ====================
# CI Gates (Prevent Future Drift)
# ====================

check-tools:
	@echo "🔍 Verifying CI tools availability..."
	@cd api-gateway/gateway && python -c "import ruff" 2>/dev/null || { echo "✗ ruff not available"; exit 1; }
	@cd api-gateway/gateway && python -c "import black" 2>/dev/null || { echo "✗ black not available"; exit 1; }
	@cd api-gateway/gateway && python -c "import mypy" 2>/dev/null || { echo "✗ mypy not available"; exit 1; }
	@echo "✅ All CI tools available"

check-static: check-tools lint format type-check
	@echo "✅ All static analysis passed"

lint:
	@echo "🔍 Running ruff linter..."
	@cd api-gateway/gateway && python -m ruff check src/ tests/ --config ../../ruff.toml
	@echo "✅ Ruff linting passed"

format:
	@echo "🔍 Checking black formatting..."
	@cd api-gateway/gateway && python -m black --check --line-length 120 src/ tests/
	@echo "✅ Black formatting passed"

type-check:
	@echo "🔍 Running mypy type checking..."
	@cd api-gateway/gateway && python -m mypy src/ --config-file ../../pyproject.toml || { echo "⚠️  Type checking warnings found"; }
	@echo "✅ Type checking completed"

test-contract:
	@echo "🔍 Running contract tests (200/401/422 for all routes)..."
	@cd api-gateway && PYTHONPATH=. python -m pytest -q -k "route_" tests/
	@echo "✅ Contract tests passed"

openapi:
	@curl -fsS $(BASE)/openapi.json | jq -r '.paths | keys[]' | sort

# Gateway Service Management (with HX standard 5s wait + validation)
gateway-start: require-tools
	@sudo systemctl start hx-gateway-ml.service && sleep 5 && echo "→ Validating..." && $(MAKE) -s check-port check-health && echo "HX Gateway started successfully!"

gateway-stop: require-tools
	@sudo systemctl stop hx-gateway-ml.service && sleep 5 && \
	( ! ss -lntp | grep ":$(PORT) " >/dev/null ) && echo "HX Gateway stopped successfully!" || { echo "✗ Still listening on :$(PORT)"; exit 1; }

gateway-restart: require-tools
	@sudo systemctl restart hx-gateway-ml.service && sleep 5 && echo "→ Validating..." && $(MAKE) -s check-port check-health && echo "HX Gateway restarted successfully!"

gateway-status:
	@systemctl --no-pager --full status hx-gateway-ml.service | sed -n '1,20p'

gateway-logs:
	@sudo journalctl -xeu hx-gateway-ml.service --no-pager -n 80 | tail -n 80

# RAG Testing Targets
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

rag-search-vec:
	@echo '[0.0]' | python3 -c 'import json,sys; print(json.dumps({"vector":[0.0]*1024,"limit":3}))' > /tmp/vec1024.json
	@curl -fsS -X POST "$(BASE)/v1/rag/search" \
	  -H "Content-Type: application/json" \
	  -d @/tmp/vec1024.json | jq .

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

qdrant-clear-ns:
	@curl -fsS -X POST "$(QDRANT_URL)/collections/$(COLL)/points/delete" \
	  -H "Content-Type: application/json" \
	  -d '{"filter":{"must":[{"key":"namespace","match":{"value":"$(NS)"}}]}}' | jq .

# ====================
# TTL Management & Cleanup
# ====================

rag-ttl-cleanup:  ## Run TTL cleanup to remove expired documents
	@echo "=== Running TTL Cleanup ==="
	cd $(GATEWAY_DIR) && source venv/bin/activate && \
	python3 /opt/HX-Infrastructure-/scripts/maintenance/cleanup-expired-content.py
	@echo "✅ TTL cleanup completed"

rag-ttl-preview:  ## Preview what would be cleaned up (dry-run)
	@echo "=== TTL Cleanup Preview (Dry Run) ==="
	cd $(GATEWAY_DIR) && source venv/bin/activate && \
	python3 /opt/HX-Infrastructure-/scripts/maintenance/cleanup-expired-content.py --dry-run --verbose
	@echo "✅ TTL preview completed"

rag-ttl-status:  ## Check TTL cleanup logs and cron status
	@echo "=== TTL System Status ==="
	@echo "Cron job status:"
	@sudo cat /etc/cron.d/hx-ttl-cleanup 2>/dev/null || echo "No TTL cron job installed"
	@echo ""
	@echo "Recent cleanup logs:"
	@tail -20 /var/log/hx-gateway-ml/ttl-cleanup.log 2>/dev/null || echo "No cleanup logs found"
	@echo ""
	@echo "Log directory permissions:"
	@ls -la /var/log/hx-gateway-ml/ 2>/dev/null || echo "Log directory not found"
	@echo "✅ TTL status check completed"

# ====================
# Performance & Optimization
# ====================

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

rag-verify-index: require-tools  ## Verify Qdrant field indexes are active
	@echo "=== Verifying Qdrant Field Indexes ==="
	@curl -fsS "$(QDRANT_URL)/collections/$(COLL)" | \
	  jq '{namespace: (.result.payload_schema | has("namespace")), doc_id: (.result.payload_schema | has("doc_id")), expires_at: (.result.payload_schema | has("expires_at"))}' | tee /dev/stderr | \
	  jq -e 'select(.namespace and .doc_id and .expires_at)' >/dev/null && echo "✓ Index verification completed" || { echo "✗ Missing one or more indexes"; exit 1; }

# ====================
# Orchestrator Targets
# ====================

rag-test-all: require-tools  ## Run complete RAG test flow (optimize → verify → upsert → search)
	@echo "=== Running Complete RAG Test Flow ==="
	@echo "Step 1: Optimizing indexes..."
	@$(MAKE) -s rag-optimize
	@echo "Step 2: Verifying indexes..."
	@$(MAKE) -s rag-verify-index
	@echo "Step 3: Testing document upsert..."
	@$(MAKE) -s rag-upsert-one
	@echo "Step 4: Testing search functionality..."
	@$(MAKE) -s rag-search
	@echo "✓ Complete RAG test flow successful!"
