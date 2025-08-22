# RA**Total Tasks**: `10`  
**Total Estimated Time**: `15.7 hours`

---

## 🎯 Project Overview

Implementation of a production-ready RAG document upsert endpoint following SOLID principles with write-scope authentication, idempotency, minimal telemetry, comprehensive validation, and complete test coverage.

---

## 📋 Task Execution Sequence

### **Phase 0: Test Infrastructure (2.1 hours)**

| Task ID | Description | Est. Time | Dependencies |
|---------|-------------|-----------|--------------|
| **ENG-000** | Create Comprehensive Test Suite | 2.1h | None |

### **Phase 1: SOLID Architecture Implementation (5.5 hours)**ert Endpoint - Task Summary & Execution Guide

> **Project**: RAG Document Upsert Implementation  
> **Priority**: `High`  
> **Total Tasks**: `9`  
> **Total Estimated Time**: `13.6 hours`

---

## 🎯 Project Overview

Implementation of a production-ready RAG document upsert endpoint following SOLID principles with write-scope authentication, idempotency, minimal telemetry, and comprehensive validation.

---

## 📋 Task Execution Sequence

### **Phase 1: SOLID Architecture Implementation (5.5 hours)**

| Task ID | Description | Est. Time | Dependencies |
|---------|-------------|-----------|--------------|
| **ENG-001** | Create SOLID-Compliant Models Module | 1.3h | None |
| **ENG-002** | Implement Services Module with Telemetry | 3.1h | ENG-001 |
| **ENG-003** | Create Routes Module with Write Auth | 2.7h | ENG-001, ENG-002 |
| **ENG-004** | Register Router in App Factory | 0.9h | ENG-001-003 |
| **ENG-004.5** | Configure Environment Variables | 0.5h | ENG-003 |

### **Phase 2: Deployment & Validation (3.2 hours)**

| Task ID | Description | Est. Time | Dependencies |
|---------|-------------|-----------|--------------|
| **ENG-005** | Restart Service and Verify Deployment | 0.6h | ENG-004.5 |
| **ENG-006** | Validate OpenAPI Documentation | 1.0h | ENG-005 |
| **ENG-007** | Functional Smoke Test with Auth | 1.7h | ENG-006 |

### **Phase 3: Production Hardening (2.5 hours)**

| Task ID | Description | Est. Time | Dependencies |
|---------|-------------|-----------|--------------|
| **ENG-008** | Production Hardening Implementation | 2.5h | ENG-007 |

---

## 🛡️ Key Production Features

### **Security & Authentication**
- **Write-Scope Auth**: X-HX-Admin-Key header validation
- **Environment Variables**: RAG_WRITE_KEY configuration
- **Input Sanitization**: Comprehensive request validation

### **Operational Excellence**
- **Idempotency**: Stable hash-based point IDs
- **Telemetry**: Structured logging for embed_texts and qdrant_upsert
- **Dimension Guards**: 1024-dimensional vector validation
- **Schema Hygiene**: Namespace keyword validation

### **SOLID Architecture**
- **Models**: Pydantic validation and type safety
- **Services**: Business logic separation with telemetry
- **Routes**: Controller layer with authentication
- **Separation**: Clear interface boundaries

---

## 🧪 Definition of Done Checklist

- [ ] Comprehensive test suite passes with zero external network calls
- [ ] `/v1/rag/upsert` registered and documented in OpenAPI
- [ ] Write-scope auth enforced (403 without X-HX-Admin-Key)
- [ ] Embeddings succeed via LiteLLM with proper authentication
- [ ] Qdrant upserts succeed with idempotent point IDs
- [ ] Dimension guard rejects vectors != EMBEDDING_DIM (1024)
- [ ] Namespace payload present and indexed in Qdrant
- [ ] Telemetry logs emitted for embed_texts and qdrant_upsert
- [ ] Smoke tests pass (upsert→search cycle)
- [ ] Rollback plan validated (revert commit, restart, test /healthz)

---

## 🚀 Quick Start Commands

### **Test Infrastructure & Quality Assurance**
```bash
# Run comprehensive test suite
cd /opt/HX-Infrastructure-/api-gateway && export PYTHONPATH=. && pytest -q

# Run with verbose output for debugging  
cd /opt/HX-Infrastructure-/api-gateway && export PYTHONPATH=. && pytest -v

# Test specific modules
cd /opt/HX-Infrastructure-/api-gateway && export PYTHONPATH=. && pytest tests/test_models.py -v
```

### **Environment Setup**
```bash
# Add to /etc/hx/gateway.env
EMBEDDING_DIM=1024
RAG_WRITE_KEY=supersecret
```

### **Service Management**
```bash
# Restart with validation
sudo systemctl restart hx-gateway-ml.service && sleep 5 && \
  systemctl --no-pager status hx-gateway-ml.service | head -15

# Verify OpenAPI exposure
curl -s :4010/openapi.json | jq '.paths | keys[]' | grep upsert
```

### **Functional Testing**
```bash
# Test auth protection (expect 403)
curl -i -X POST :4010/v1/rag/upsert -H 'Content-Type: application/json' \
  -d '{"documents":[{"text":"test"}]}'

# Test successful upsert (expect 200)
curl -i -X POST :4010/v1/rag/upsert \
  -H 'X-HX-Admin-Key: supersecret' \
  -H 'Content-Type: application/json' \
  -d '{"documents":[{"text":"Citadel is Hana-X internal AI OS","namespace":"docs:test"}]}'

# Verify search works
curl -sS -X POST :4010/v1/rag/search -H 'Content-Type: application/json' \
  -d '{"query":"What is Citadel?","limit":3,"namespace":"docs:test"}' | jq .
```

---

## 🔄 Rollback Procedure

```bash
# Emergency rollback if deployment fails
sudo journalctl -u hx-gateway-ml.service -n 100 --no-pager
git -C /opt/HX-Infrastructure-/api-gateway checkout <prev-commit>
sudo systemctl restart hx-gateway-ml.service && sleep 5
curl -s :4010/healthz | jq .
```

---

## 📊 Progress Tracking

- **Current Status**: `Ready for Implementation`
- **Total Progress**: `10% (1/10 tasks completed - Test Infrastructure)`
- **Next Action**: Execute ENG-000 (Create Test Suite) then ENG-001 (Create Models Module)
- **Critical Path**: ENG-000 → ENG-001 → ENG-002 → ENG-003 → ENG-004.5 → ENG-005

---

## 📚 References

- **Architecture**: SOLID principles with models/services/routes separation
- **Security**: Write-scope authentication with environment-based keys
- **Telemetry**: Structured logging for operational visibility
- **Validation**: Comprehensive input validation and dimension guards
- **Testing**: End-to-end functional testing with authentication
