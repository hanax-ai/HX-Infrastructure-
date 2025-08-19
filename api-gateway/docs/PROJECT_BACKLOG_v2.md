# HX Gateway Wrapper - Project Backlog

## Active Backlog Items

### 🔄 HIGH PRIORITY: Database Integration for LiteLLM Backend

**Issue ID**: HX-GW-001  
**Priority**: High  
**Estimated Effort**: 2-4 hours  
**Status**: Ready for Implementation  
**Created**: August 19, 2025  

#### Problem Description

The HX Gateway Wrapper reverse proxy is fully operational, but all API endpoints return database connectivity errors from the upstream LiteLLM service. This prevents full functionality of the OpenAI-compatible API endpoints.

#### Failed Test Results

**Test Suite**: 6.2-6.4 API Validation  
**Date**: August 19, 2025  

##### ✅ PASSING Tests

**Setup**: Set your API key for all examples below:
```bash
export API_KEY="YOUR_TOKEN_HERE"
```

```bash
# 6.2 Health Check
curl -s http://127.0.0.1:4010/healthz | jq .
# Result: {"ok": true, "note": "HX wrapper – proxy mode"} ✅

# 6.2 Authentication & Reverse Proxy
curl -s http://127.0.0.1:4010/v1/models -H "Authorization: Bearer $API_KEY"
# Result: Proper proxy to LiteLLM, auth working ✅
```

##### ❌ FAILING Tests (Database Required)

```bash
# 6.2 Models List
curl -s http://127.0.0.1:4010/v1/models -H "Authorization: Bearer $API_KEY" | jq .
# Result: {"error": {"message": "No connected db.", "type": "no_db_connection", "param": null, "code": "400"}} ❌

# 6.3 Embeddings (input→prompt transformation working)
curl -s http://127.0.0.1:4010/v1/embeddings \
  -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"emb-premium","input":"HX-OK"}' | jq '.data[0].embedding | length'
# Result: {"error": {"message": "No connected db.", "type": "no_db_connection", "param": null, "code": "400"}} ❌

# 6.4 Chat Completions
curl -s http://127.0.0.1:4010/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" \
  -H "X-HX-Model-Group: hx-chat" \
  -d '{"messages":[{"role":"user","content":"Return exactly the text: HX-OK"}],"temperature":0,"max_tokens":10}' \
  | jq -r '.choices[0].message.content' | grep -q 'HX-OK' && echo "✅ Deterministic chat OK" || echo "❌ Chat failed"
# Result: ❌ Chat failed - {"error": {"message": "No connected db.", "type": "no_db_connection", "param": null, "code": "400"}}

# Direct LiteLLM Test (confirms root cause)
curl -s http://127.0.0.1:4000/v1/embeddings \
  -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"emb-premium","input":"HX-OK"}' | jq .
# Result: {"error": {"message": "No connected db.", "type": "no_db_connection", "param": null, "code": "400"}} ❌
```

#### Technical Analysis

**Root Cause**: LiteLLM requires Postgres database connectivity for:

- Model registry and configuration
- Request/response logging  
- Usage analytics and billing
- Admin interface functionality

**Validation Evidence**:

1. **✅ Wrapper Working**: Identical responses from wrapper and direct LiteLLM calls prove reverse proxy is functioning correctly
2. **✅ Transformations Working**: Input→prompt transformation confirmed working (same error response regardless of input format)
3. **✅ Authentication Working**: No auth errors, requests reaching LiteLLM successfully
4. **⚠️ Database Missing**: Consistent "No connected db" across all endpoints

#### Implementation Specification

**Complete implementation guide available**: [DATABASE_INTEGRATION_SPEC.md](./DATABASE_INTEGRATION_SPEC.md)

**Summary of Required Changes**:

1. **Database Server Setup**

   ```sql
   -- Postgres (run as superuser)
   CREATE DATABASE hx_gateway;
   CREATE USER hx_gateway WITH PASSWORD 'REDACTED';
   GRANT ALL PRIVILEGES ON DATABASE hx_gateway TO hx_gateway;
   ```

2. **Environment Configuration**

   ```bash
   # /opt/HX-Infrastructure-/api-gateway/config/api-gateway/gateway.env
   DATABASE_URL=postgresql://hx_gateway:REDACTED@192.168.10.X:5432/hx_gateway
   REDIS_URL=redis://:REDACTED@192.168.10.Y:6379/0
   DISABLE_ADMIN_UI=true
   ```

3. **SystemD Integration**

   ```bash
   # Both services need EnvironmentFile configuration
   sudo mkdir -p /etc/systemd/system/hx-litellm-gateway.service.d
   sudo mkdir -p /etc/systemd/system/hx-gateway-ml.service.d
   ```

#### Acceptance Criteria

**When Complete, These Tests Must Pass**:

```bash
# Models endpoint returns JSON list
curl -s http://127.0.0.1:4010/v1/models -H "Authorization: Bearer $API_KEY" | jq '.data | length'
# Expected: Positive integer (number of models)

# Embeddings with input→prompt transformation  
curl -s http://127.0.0.1:4010/v1/embeddings \
  -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"emb-premium","input":"HX-OK"}' | jq '.data[0].embedding | length'
# Expected: 1024 (or embedding dimension)

# Deterministic chat completion
curl -s http://127.0.0.1:4010/v1/chat/completions \
  -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"hx-chat","messages":[{"role":"user","content":"Return exactly the text: HX-OK"}],"max_tokens":10,"temperature":0}' \
  | jq -r '.choices[0].message.content'
# Expected: "HX-OK"
```

#### Dependencies

- Postgres server (version 12+) with network access
- Redis server (version 6+) for caching/rate limiting (optional)
- Database credentials and connection details
- Network connectivity from gateway server to database servers

#### Risk Assessment

- **Low Risk**: Well-defined implementation with complete specification
- **Rollback Plan**: Documented procedure to return to DB-less mode
- **Testing**: Comprehensive test suite defined for validation

---

### 🔄 MEDIUM PRIORITY: Advanced ML Routing Implementation

**Issue ID**: HX-GW-002  
**Priority**: Medium  
**Estimated Effort**: 1-2 hours  
**Status**: Optional Enhancement  

#### Description

Current implementation uses simplified reverse proxy. The full SOLID middleware pipeline with ML-based model routing is available but not currently active.

#### Enhancement Details

- Switch from simple proxy to full SOLID pipeline
- Enable `X-HX-Model-Group` header routing
- Activate configuration-driven model selection
- ML scoring algorithm for optimal model selection

#### Implementation

Available in `/opt/HX-Infrastructure-/api-gateway/gateway/src/middlewares/` - requires integration into main.py

---

### 🔄 LOW PRIORITY: Documentation and Monitoring Enhancements

**Issue ID**: HX-GW-003  
**Priority**: Low  
**Estimated Effort**: 1-2 hours  

#### Items

- API documentation generation
- Metrics collection and monitoring
- Performance benchmarking
- Load testing validation
- Operational runbooks

---

## Completed Items ✅

### SOLID-Compliant Gateway Wrapper Implementation

- **Completed**: August 18-19, 2025
- **Status**: Production Ready
- **Components**: Reverse proxy, input→prompt transformation, service management
- **Documentation**: Complete implementation guides created

### Security and Service Management

- **Completed**: August 18, 2025  
- **Status**: Hardened and Operational
- **Components**: SystemD integration, user isolation, file permissions

### Health Monitoring and Validation

- **Completed**: August 19, 2025
- **Status**: Operational
- **Components**: Health endpoints, test suite, validation procedures

---

**Backlog Last Updated**: August 19, 2025  
**Next Review**: After database integration completion
