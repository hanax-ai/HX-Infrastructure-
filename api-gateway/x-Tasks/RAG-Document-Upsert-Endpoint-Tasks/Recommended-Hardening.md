# RAG System Hardening Roadmap
## Production-Ready Battle-Testing & Operational Excellence

### 🔒 1. Security Hardening (Priority: HIGH)

**Secrets Management:**
- ✅ Centralized secrets in `/etc/hx/secrets.env` as single source of truth
- ✅ Rotate keys only in one location
- 🔄 **NEXT**: Implement key rotation automation

**SystemD Security Lockdown:**
```ini
# /etc/systemd/system/hx-gateway-ml.service.d/hardening.conf
[Service]
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
NoNewPrivileges=true
CapabilityBoundingSet=
RestrictSUIDSGID=true
ProtectHostname=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ReadWritePaths=/var/lib/hx-gateway
```

**Deployment Command:**
```bash
sudo systemctl daemon-reload && sudo systemctl restart hx-gateway-ml.service && sleep 5
```

---

### 📊 2. Observability & SLOs (Priority: HIGH)

**Structured Logging Requirements:**
- Emit JSON logs with: `request_id`, `namespace`, `operation`, `latency_ms`, `result`, `error`
- Mask secrets in all log output
- Hash admin keys for audit trails

**Prometheus Metrics Targets:**
- Embedding latency: p50/p95
- Qdrant search/upsert latency: p50/p95  
- Throughput: upserts/sec, errors/sec
- Circuit breaker: queue/backoff counts

**Service Level Objectives:**
- **Availability**: 99.9% uptime
- **Performance**: p95 search < 200ms (vector), p95 embed+search < 800ms
- **Error Rate**: < 0.1% for valid requests

**Implementation Path:**
- Add `/metrics` endpoint or sidecar when convenient
- Integrate with existing Prometheus/Grafana stack

---

### 🚀 3. API Quality & Developer Experience (Priority: MEDIUM)

**OpenAPI Improvements:**
```python
app = FastAPI(
    title="HX API Gateway",
    generate_unique_id_function=lambda route: f"{route.name}_{route.path.replace('/', '_')}_{'_'.join(route.methods)}"
)
```

**HTTP Standards:**
- ✅ Add CORS for UI/cross-origin clients
- ✅ Deterministic error codes:
  - `400`: Dimension mismatch, validation errors
  - `401/403`: Authentication/authorization failures  
  - `429`: Rate limiting/throttling
  - `503`: Circuit breaker, upstream unavailable

---

### 🎯 4. Data Model & Validation (Priority: HIGH)

**Vector Validation:**
- ✅ Dimension guard: enforce 1024 dimensions
- 🔄 **NEXT**: Bulk vector validation in batches
- 🔄 **NEXT**: Validate vector ranges and NaN detection

**Stable Document IDs:**
- ✅ Current: `hash(namespace + text)`
- 🔄 **NEXT**: Accept client-supplied IDs for versioned sources
- 🔄 **NEXT**: Implement `(doc_id, chunk_id)` composite keys

**Metadata Schema Standards:**
```json
{
  "source_uri": "https://docs.example.com/page",
  "doc_id": "uuid-or-stable-id", 
  "chunk_id": "chunk-001",
  "updated_at": "2025-08-21T10:30:00Z",
  "checksum": "sha256:abc123...",
  "title": "Document Title",
  "section": "Chapter 3"
}
```

**Benefits Unlocked:**
- Duplicate suppression
- Partial re-upserts  
- Auditable lineage
- Version management

---

### 🗑️ 5. Document Lifecycle Management (Priority: MEDIUM)

**Deletion Endpoints:**
```bash
DELETE /v1/rag/documents?id=document-123
POST /v1/rag/delete_by_namespace  # Filter-based bulk delete
```

**TTL Implementation:**
- Optional `ttl_days` in upsert payload
- Nightly reaper process for expired documents
- Configurable retention policies per namespace

---

### 📚 6. Content Processing (Priority: LOW)

**Document Adapters:**
- Markdown processor with heading preservation
- HTML cleaner and text extraction
- PDF text extraction (via pypdf or similar)
- Plain text with encoding detection

**Chunking Strategy:**
- Default: `max_tokens≈512`, `overlap≈64`
- Preserve headings/structure in metadata
- Sentence boundary awareness
- Idempotent chunking: `(doc_id, chunk_id)` stability

---

### 🛡️ 7. Resilience & Circuit Breaking (Priority: HIGH)

**Retry Logic:**
- Qdrant operations: 100ms/300ms/700ms with jitter
- Embedding calls: exponential backoff
- Idempotent operations only

**Circuit Breaker Pattern:**
- Monitor embedding service health
- Fall back to queue or return `503` with `Retry-After`
- Graceful degradation modes

---

### 🔐 8. Access Control & Resource Management (Priority: MEDIUM)

**Authentication:**
- ✅ Continue requiring `X-HX-Admin-Key` for writes
- ✅ Bearer token validation for reads
- 🔄 **NEXT**: Role-based access control

**Quotas & Rate Limiting:**
- Per-namespace limits: docs/day, MB/day
- Request rate limiting by client/key
- Graceful quota enforcement with clear error messages

**Audit & Security:**
- Mask secrets in all logs
- Hash admin keys for audit trails
- Request/response logging for compliance

---

### 💾 9. Backup & Disaster Recovery (Priority: HIGH)

**Qdrant Backup Strategy:**
- Daily snapshots with 7-day retention
- Weekly snapshots with 4-week retention  
- Automated backup verification

**Database Backup:**
- SQLite: Hot copy nightly to `/var/backups/hx/`
- Migration path: SQLite → PostgreSQL when scale requires

**Recovery Documentation:**
- 10-minute restore runbook
- RTO/RPO definitions
- Tested recovery procedures

---

### 🔧 10. Operational Tooling (Priority: MEDIUM)

**Enhanced Make Targets:**
```makefile
secrets-edit:
	@sudo ${EDITOR:-vi} /etc/hx/secrets.env

secrets-rotate:
	@sudo systemctl restart hx-gateway-ml.service && sleep 5 && echo "Gateway reloaded"
	@sudo systemctl restart hx-litellm-gateway.service || true && sleep 5 && echo "LiteLLM reloaded"
```

**CI/CD Pipeline:**
- Unit tests with mocked network calls
- Integration tests against test environment
- Code quality: `pyflakes`, `black --check`, `isort -c`
- Security scanning and dependency updates

---

### ✅ Final Acceptance Criteria

**Functional Validation:**
1. **Upsert Success**: Text → HTTP 200, proper embedding generated
2. **Search Success**: Query → `status:"ok"`, finds documents in correct namespace
3. **Validation**: Bad vector length → HTTP 4xx with clear error message  
4. **Idempotency**: Re-upsert same text → Qdrant count unchanged
5. **Service Resilience**: Restart → health OK, routes present, port listening, logs clean

**Operational Readiness:**
- All monitoring metrics collecting
- Backup procedures tested and documented
- Security hardening applied and verified
- Team runbooks complete and tested

2) Metrics, logs, SLOs

Emit structured JSON logs (request_id, namespace, op, latency_ms, result, error).

Prometheus scrape targets:

embedding latency p50/p95,

qdrant search/upsert latency p50/p95,

upserts/sec, errors/sec,

queue/backoff counts.

SLOs to start: Availability 99.9%, p95 search < 200ms (vector), p95 embed+search < 800ms.

Add /metrics (or sidecar) when convenient.

3) API quality & DX

Avoid OpenAPI duplicate op IDs (your warning from before). In FastAPI:

app = FastAPI(
    title="HX API Gateway",
    generate_unique_id_function=lambda route: f"{route.name}_{route.path.replace('/', '_')}_{'_'.join(route.methods)}"
)


Add CORS (if UI or cross-origin clients will call).

Return deterministic error codes (e.g., 400 for dim mismatch; 401/403 for auth; 429 for throttling).

4) Data model hygiene

Dimension guard: you’re enforcing 1024—great. Also validate all bulk vectors in a batch.

Stable IDs: keep hash(namespace + text); also accept client-supplied id for versioned sources.

Metadata schema: reserve source_uri, doc_id, chunk_id, updated_at, checksum. That unlocks:

Duplicate suppression,

Partial re-upserts,

Auditable lineage.

5) Deletion & TTL

Implement a minimal delete:

DELETE /v1/rag/documents?id=...

POST /v1/rag/delete_by_namespace (filter-based)

Optional TTL in payload (e.g., ttl_days) + a nightly reaper.

6) Content loaders (quick wins)

Adapters: Markdown, HTML, PDF (text), and plain text.

Chunker defaults: max_tokens≈512, overlap≈64, preserve headings in metadata.

Idempotent upsert: (doc_id, chunk_id) key.

7) Resiliency

Add retries/backoff around Qdrant and embeddings (e.g., 100/300/700ms jitter).

Circuit-breaker on embeddings if upstream misbehaves; fall back to queue or return 503 with Retry-After.

8) Access control & quotas

Continue requiring X-HX-Admin-Key for writes.

Per-namespace quotas (docs/day, MB/day).

Mask secrets in logs; hash admin keys for audit.

9) Backups & DR

Qdrant snapshot cron + retention (daily x 7, weekly x 4).

SQLite (if used) hot copy nightly to /var/backups/hx/ (or move to Postgres soon).

Document a 10-minute restore runbook.

10) Tooling polish (Make + CI)

Add quick rotate + restart helpers:

secrets-edit:
  @sudo ${EDITOR:-vi} /etc/hx/secrets.env

secrets-rotate:
  @sudo systemctl restart hx-gateway-ml.service && sleep 5 && echo "Gateway reloaded"
  @sudo systemctl restart hx-litellm-gateway.service || true && sleep 5 && echo "LiteLLM reloaded"


CI: run unit + integration tests (mocked network), pyflakes, black --check, isort -c.

Minimal functional acceptance (final validation)

Upsert text → 200; search(query) → status:"ok" and finds it in the right namespace.

Upsert bad vector length → 4xx with clear message.

Re-upsert same text → count unchanged in Qdrant (idempotent).

Restart service → health OK, routes present, port listening, logs clean.