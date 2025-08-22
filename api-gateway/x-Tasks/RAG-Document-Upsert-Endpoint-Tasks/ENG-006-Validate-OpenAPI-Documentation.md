# Engineering Task: Validate OpenAPI Documentation and Endpoint Exposure

> **Task ID**: `ENG-006`  
> **Priority**: `High`  
> **Assigned To**: `Infrastructure Team`  
> **Due Date**: `2025-08-21`

---

## 🎯 Objective

Validate that the new RAG upsert endpoint is properly exposed through OpenAPI documentation and accessible via the gateway service.

---

## 🏗️ Infrastructure Context

- **Component**: `api-gateway`
- **Service Impact**: `hx-gateway-ml.service (port 4010) - Testing only`
- **Network Changes**: `No`
- **Rollback Plan**: `N/A - Validation only`

---

## ⚠️ Risk Assessment

- **Risk Level**: `Low`
- **Potential Impact**: Validation testing only, no modifications to running system
- **Mitigation**: Read-only operations with comprehensive endpoint testing
- **Dependencies**: ENG-005 (Service Restart) must be completed first

---

## ✅ Execution Plan

### Step 0: Verify Preconditions/Pre-Flight

*Ensure all necessary environment permissions, directories, files, variables, configurations, and database migrations are in place before starting.*

1. **Verify service is running** *(Est: 0.1 hours)*
   - Check hx-gateway-ml.service is active
   - Verify port 4010 is responding
2. **Confirm OpenAPI endpoint accessible** *(Est: 0.1 hours)*
   - Test `/docs` endpoint responds
   - Verify `/openapi.json` is accessible
3. **Check existing endpoints still work** *(Est: 0.1 hours)*
   - Test health endpoint
   - Verify existing RAG search functionality

### Implementation Steps

1. **Test OpenAPI documentation endpoint** *(Est: 0.2 hours)*

   ```bash
   curl -f http://localhost:4010/docs
   curl -f http://localhost:4010/openapi.json
   ```

2. **Validate RAG upsert endpoint appears in OpenAPI** *(Est: 0.3 hours)*
   - Check `/openapi.json` contains upsert endpoint
   - Verify proper request/response schemas
   - Confirm endpoint documentation is complete

3. **Test endpoint accessibility** *(Est: 0.2 hours)*
   - Verify endpoint responds to OPTIONS request
   - Check proper HTTP methods are exposed
   - Validate authentication requirements

4. **Verify OpenAPI schema completeness** *(Est: 0.2 hours)*
   - Check all models are properly documented
   - Verify request/response examples exist
   - Confirm proper tags and descriptions

---

## 🧪 Validation Criteria

### Must-Pass Validations

1. **Service Health**: Gateway service remains operational during testing
2. **End-to-End**: OpenAPI documentation includes new RAG upsert endpoint  
3. **Performance**: OpenAPI generation doesn't impact service performance
4. **Security**: Endpoint appears with proper authentication requirements

### Test Case

- **Description**: Validate RAG upsert endpoint is properly documented and exposed via OpenAPI
- **Expected Result**: Endpoint appears in OpenAPI docs with complete schema documentation

### Test Steps

1. Verify OpenAPI docs endpoint responds
2. Check upsert endpoint appears in schema
3. Validate request/response models are documented
4. Confirm endpoint is accessible for testing

### Test Commands

```bash
# Test OpenAPI docs accessibility
curl -s -o /dev/null -w "%{http_code}" http://localhost:4010/docs

# Check if upsert endpoint exists in OpenAPI schema
curl -s http://localhost:4010/openapi.json | jq '.paths | keys[]' | grep -i upsert && echo "✅ Upsert route present"

# Verify endpoint schema
curl -s http://localhost:4010/openapi.json | jq '.paths["/v1/rag/upsert"]'

# Check models are documented
curl -s http://localhost:4010/openapi.json | jq '.components.schemas | keys[]' | grep -i upsert

# Test endpoint responds to OPTIONS
curl -X OPTIONS -s -o /dev/null -w "%{http_code}" http://localhost:4010/v1/rag/upsert

# Verify endpoint documentation completeness
curl -s http://localhost:4010/openapi.json | jq '.paths["/v1/rag/upsert"].post | keys[]'
```

---

## 📊 Status Tracking

- **Current Status**: `Not Started`
- **Completion**: `0%`
- **Time Estimated**: `1.0 hours`
- **Time Actual**: `[To be filled]`
- **Last Updated**: `2025-08-21`
- **Blocked By**: `ENG-005 (Service Restart)`

### Change Log

- **2025-08-21**: Task created based on SOLID-compliant RAG upsert requirements

---

## 📎 Additional Information

### Requirements

- ENG-005 (Service Restart) must be completed first
- Service must be running and responsive
- OpenAPI documentation must be complete and accurate
- Endpoint must be properly accessible

### Notes

- This is a validation-only task with no system modifications
- OpenAPI schema should include complete request/response documentation
- Endpoint should be testable via Swagger UI

---

## 📚 References

- **Related Issues**: RAG Document Upsert Endpoint Implementation
- **Documentation**: `/opt/HX-Infrastructure-/api-gateway/x-Tasks/RAG-Document-Upsert-Endpoint-Tasks/RAG-Doc-Upsert-2.md`
- **Architecture Notes**: OpenAPI documentation validation and endpoint exposure verification
- **Dependencies**: Requires ENG-005 completion, blocks ENG-007 (Functional Testing)
