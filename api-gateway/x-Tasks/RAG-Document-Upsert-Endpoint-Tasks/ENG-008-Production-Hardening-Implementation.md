# Engineering Task: Implement Production Hardening with Dimension Guards and Schema Hygiene

> **Task ID**: `ENG-008`  
> **Priority**: `Medium`  
> **Assigned To**: `Infrastructure Team`  
> **Due Date**: `2025-08-22`

---

## 🎯 Objective

Implement production hardening features including 1024-dimensional vector validation guards and schema hygiene for namespace keywords as specified in the hardening requirements document.

---

## 🏗️ Infrastructure Context

- **Component**: `api-gateway`
- **Service Impact**: `hx-gateway-ml.service (port 4010) - Minor modifications`
- **Network Changes**: `No`
- **Rollback Plan**: `Revert hardening changes and restart service if validation issues occur`

---

## ⚠️ Risk Assessment

- **Risk Level**: `Low`
- **Potential Impact**: Enhanced validation may reject previously acceptable inputs
- **Mitigation**: Comprehensive testing of validation logic before deployment
- **Dependencies**: ENG-007 (Functional Testing) must be completed first

---

## ✅ Execution Plan

### Step 0: Verify Preconditions/Pre-Flight

*Ensure all necessary environment permissions, directories, files, variables, configurations, and database migrations are in place before starting.*

1. **Verify functional testing completed successfully** *(Est: 0.1 hours)*
   - Check ENG-007 was completed and validated
   - Confirm basic upsert functionality works
2. **Review current implementation** *(Est: 0.2 hours)*
   - Examine existing validation in services module
   - Identify areas requiring hardening
3. **Prepare hardening test cases** *(Est: 0.2 hours)*
   - Create test payloads with invalid dimensions
   - Prepare namespace validation test cases

### Implementation Steps

1. **Implement 1024-dimensional vector validation guard** *(Est: 0.8 hours)*
   - Add embedding dimension validation in services module
   - Implement checks for vector size consistency
   - Add proper error messages for dimension mismatches

2. **Add schema hygiene for namespace keywords** *(Est: 0.6 hours)*
   - Implement namespace validation rules
   - Add keyword sanitization and validation
   - Ensure proper metadata schema enforcement

3. **Enhance error handling and logging** *(Est: 0.4 hours)*
   - Add structured logging for validation failures
   - Implement proper HTTP error responses
   - Include helpful error messages for debugging

4. **Add input sanitization and validation** *(Est: 0.5 hours)*
   - Implement content length limits
   - Add metadata field validation
   - Ensure proper request sanitization

---

## 🧪 Validation Criteria

### Must-Pass Validations

1. **Service Health**: Gateway service remains operational with enhanced validation
2. **End-to-End**: Validation correctly rejects invalid inputs while accepting valid ones  
3. **Performance**: Validation doesn't significantly impact processing time
4. **Security**: Proper input sanitization prevents injection attacks

### Definition of Done (Production Ready)

1. **API Exposure**: `/v1/rag/upsert` registered and documented in OpenAPI
2. **Authentication**: Write-scope auth enforced (403 without X-HX-Admin-Key)
3. **Embeddings**: Succeed via LiteLLM with proper authentication
4. **Vector Storage**: Qdrant upserts succeed with idempotent point IDs
5. **Validation**: Dimension guard rejects vectors != EMBEDDING_DIM (1024)
6. **Indexing**: Namespace payload present and indexed in Qdrant
7. **Telemetry**: Logs emitted for embed_texts and qdrant_upsert operations
8. **Testing**: Smoke tests pass (upsert→search cycle)
9. **Rollback**: Revert to previous commit, restart service, validate /healthz

### Test Case

- **Description**: Validate production hardening features work correctly with comprehensive validation
- **Expected Result**: Invalid inputs are properly rejected with helpful error messages

### Test Steps

1. Test dimension validation with incorrect vector sizes
2. Verify namespace validation with invalid keywords
3. Test input sanitization with edge cases
4. Confirm valid inputs still process correctly

### Test Commands

```bash
# Test dimension validation (should fail)
curl -X POST http://localhost:4010/v1/rag/upsert \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: supersecret" \
  -d '{"documents": [{"text": "test", "metadata": {"namespace": "test"}}]}' \
  | jq '.error' || echo "Expected dimension validation error"

# Test namespace validation (should fail with invalid namespace)
curl -X POST http://localhost:4010/v1/rag/upsert \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: supersecret" \
  -d '{"documents": [{"text": "test", "metadata": {"namespace": "invalid@namespace!"}}]}' \
  | jq '.error' || echo "Expected namespace validation error"

# Test valid input (should succeed)
curl -X POST http://localhost:4010/v1/rag/upsert \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: supersecret" \
  -d '{"documents": [{"text": "Valid test document content", "metadata": {"namespace": "test-valid"}}]}' \
  | jq '.status' || echo "Expected successful upsert"

# Test content length validation
curl -X POST http://localhost:4010/v1/rag/upsert \
  -H "Content-Type: application/json" \
  -H "X-HX-Admin-Key: supersecret" \
  -d '{"documents": [{"text": "", "metadata": {"namespace": "test"}}]}' \
  | jq '.error' || echo "Expected content length validation error"

# Check validation error logging
sudo journalctl -u hx-gateway-ml.service --since="5 minutes ago" | grep -i validation

# Verify rollback capability
git -C /opt/HX-Infrastructure-/api-gateway log --oneline -5
echo "✅ Rollback plan: git checkout <prev-commit> && sudo systemctl restart hx-gateway-ml.service"
```

---

## 📊 Status Tracking

- **Current Status**: `Not Started`
- **Completion**: `0%`
- **Time Estimated**: `2.5 hours`
- **Time Actual**: `[To be filled]`
- **Last Updated**: `2025-08-21`
- **Blocked By**: `ENG-007 (Functional Testing)`

### Change Log

- **2025-08-21**: Task created based on production hardening requirements

---

## 📎 Additional Information

### Requirements

- ENG-007 (Functional Testing) must be completed first
- Implement 1024-dimensional vector validation guards
- Add namespace schema hygiene and validation
- Proper error handling and logging

### Notes

- Hardening features should improve security and data quality
- Validation should be comprehensive but not overly restrictive
- Error messages should be helpful for debugging

---

## 📚 References

- **Related Issues**: RAG Document Upsert Endpoint Implementation
- **Documentation**: `/opt/HX-Infrastructure-/api-gateway/x-Tasks/RAG-Document-Upsert-Endpoint-Tasks/RAG-Doc-Upsert-1.md`
- **Architecture Notes**: Production hardening with comprehensive validation and security measures
- **Dependencies**: Requires ENG-007 completion, final task in implementation sequence
