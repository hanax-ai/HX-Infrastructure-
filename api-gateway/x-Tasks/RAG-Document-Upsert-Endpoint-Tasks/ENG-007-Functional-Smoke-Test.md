# Engineering Task: Functional Smoke Test with Document Upsert and Search Verification

> **Task ID**: `ENG-007`  
> **Priority**: `High`  
> **Assigned To**: `Infrastructure Team`  
> **Due Date**: `2025-08-21`

---

## 🎯 Objective

Perform comprehensive functional testing of the RAG upsert endpoint, including document insertion and subsequent search verification to ensure end-to-end functionality works correctly.

---

## 🏗️ Infrastructure Context

- **Component**: `api-gateway`
- **Service Impact**: `hx-gateway-ml.service (port 4010) - Testing with data insertion`
- **Network Changes**: `No`
- **Rollback Plan**: `Clean up test documents from Qdrant collection if needed`

---

## ⚠️ Risk Assessment

- **Risk Level**: `Medium`
- **Potential Impact**: Test data insertion into production Qdrant collection
- **Mitigation**: Use clearly marked test documents, clean up test data after validation
- **Dependencies**: ENG-006 (OpenAPI Validation) must be completed first

---

## ✅ Execution Plan

### Step 0: Verify Preconditions/Pre-Flight

*Ensure all necessary environment permissions, directories, files, variables, configurations, and database migrations are in place before starting.*

1. **Verify service and endpoints are operational** *(Est: 0.1 hours)*
   - Check gateway service is running
   - Verify OpenAPI documentation includes upsert endpoint
2. **Confirm Qdrant collection health** *(Est: 0.1 hours)*
   - Test Qdrant connection
   - Verify `hx_rag_default` collection exists and is accessible
3. **Prepare test data** *(Est: 0.1 hours)*
   - Create sample test documents
   - Define test namespace for isolation

### Implementation Steps

1. **Create test document payload** *(Est: 0.2 hours)*

   ```bash
   cat > /tmp/test-upsert-payload.json << 'EOF'
   {
     "documents": [
       {
         "text": "Citadel is Hana-X's internal AI OS for orchestrating LLM and RAG.",
         "namespace": "docs:test",
         "metadata": {
           "source": "functional-test",
           "title": "Citadel Test Document"
         }
       }
     ]
   }
   EOF
   ```

2. **Test document upsert operation with write auth** *(Est: 0.4 hours)*
   - Send POST request to `/v1/rag/upsert` endpoint with X-HX-Admin-Key
   - Test 403 response without authentication header
   - Verify successful response with proper authentication

3. **Verify document was stored in Qdrant** *(Est: 0.3 hours)*
   - Query Qdrant directly to confirm document exists
   - Verify embedding was generated (1024 dimensions)
   - Check metadata was stored correctly

4. **Test search functionality with upserted document** *(Est: 0.4 hours)*
   - Use existing RAG search endpoint to find test document
   - Verify test document appears in search results
   - Confirm relevance scoring works correctly

5. **Validate telemetry logging** *(Est: 0.2 hours)*
   - Check service logs for embedding and upsert telemetry
   - Verify timing and status information is logged
   - Confirm operational visibility

6. **Clean up test data** *(Est: 0.2 hours)*
   - Remove test documents from Qdrant collection
   - Verify cleanup was successful

---

## 🧪 Validation Criteria

### Must-Pass Validations

1. **Service Health**: Gateway service remains operational during testing
2. **End-to-End**: Complete upsert and search cycle works successfully  
3. **Performance**: Operations complete within reasonable time limits
4. **Security**: Authentication works correctly for all operations

### Test Case

- **Description**: Full end-to-end test of RAG upsert and search functionality
- **Expected Result**: Document is successfully upserted, stored in Qdrant, and retrievable via search

### Test Steps

1. Submit test document via upsert endpoint
2. Verify successful upsert response
3. Confirm document exists in Qdrant
4. Search for document using existing RAG search
5. Clean up test data

### Test Commands

```bash
# Test authentication failure (should return 403)
curl -X POST http://localhost:4010/v1/rag/upsert \
  -H "Content-Type: application/json" \
  -d @/tmp/test-upsert-payload.json \
  -w "%{http_code}" -o /dev/null | grep -q "403" && echo "✅ Auth protection working"

# Test document upsert with authentication
curl -X POST http://localhost:4010/v1/rag/upsert \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: supersecret" \
  -d @/tmp/test-upsert-payload.json

# Test search functionality
curl -X POST http://localhost:4010/v1/rag/search \
  -H "Content-Type: application/json" \
  -d '{"query": "What is Citadel?", "limit": 3, "namespace": "docs:test"}' | jq .

# Check telemetry logs
sudo journalctl -u hx-gateway-ml.service --since="5 minutes ago" | grep -E "(qdrant_upsert|embed_texts)" && echo "✅ Telemetry logging working"

# Clean up test data (example command)
curl -X POST http://localhost:6333/collections/hx_rag_default/points/delete \
  -H "Content-Type: application/json" \
  -d '{"filter": {"must": [{"key": "metadata.source", "match": {"value": "functional-test"}}]}}'

# Verify cleanup
curl -X POST http://localhost:4010/v1/rag/search \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-hx-dev-1234" \
  -d '{"query": "test document RAG upsert functionality", "namespace": "test-rag-upsert", "limit": 5}'
```

---

## 📊 Status Tracking

- **Current Status**: `Not Started`
- **Completion**: `0%`
- **Time Estimated**: `1.7 hours`
- **Time Actual**: `[To be filled]`
- **Last Updated**: `2025-08-21`
- **Blocked By**: `ENG-006 (OpenAPI Validation)`

### Change Log

- **2025-08-21**: Task created based on SOLID-compliant RAG upsert requirements

---

## 📎 Additional Information

### Requirements

- ENG-006 (OpenAPI Validation) must be completed first
- Qdrant collection must be accessible and functional
- LiteLLM authentication must be working
- Existing RAG search endpoint must be operational

### Notes

- This task validates the complete RAG upsert workflow
- Test data should be clearly marked and cleaned up
- Both upsert and search functionality must work together

---

## 📚 References

- **Related Issues**: RAG Document Upsert Endpoint Implementation
- **Documentation**: `/opt/HX-Infrastructure-/api-gateway/x-Tasks/RAG-Document-Upsert-Endpoint-Tasks/RAG-Doc-Upsert-2.md`
- **Architecture Notes**: End-to-end functional testing with data validation
- **Dependencies**: Requires ENG-006 completion, blocks ENG-008 (Hardening Implementation)
