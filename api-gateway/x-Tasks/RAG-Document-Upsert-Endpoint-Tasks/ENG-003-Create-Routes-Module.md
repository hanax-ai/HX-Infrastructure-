# Engineering Task: Create RAG Upsert Routes Module

> **Task ID**: `ENG-003`  
> **Priority**: `High`  
> **Assigned To**: `Infrastructure Team`  
> **Due Date**: `2025-08-21`

---

## 🎯 Objective

Create the API routes module for RAG document upsert operations, implementing the controller layer of the SOLID architecture with proper FastAPI integration and OpenAPI documentation.

---

## 🏗️ Infrastructure Context

- **Component**: `api-gateway`
- **Service Impact**: `hx-gateway-ml.service (port 4010)`
- **Network Changes**: `No`
- **Rollback Plan**: `Delete the routes module and remove router registration from app.py`

---

## ⚠️ Risk Assessment

- **Risk Level**: `Medium`
- **Potential Impact**: New API endpoint exposure with potential for misuse if not properly validated
- **Mitigation**: Comprehensive input validation, rate limiting considerations, and thorough testing
- **Dependencies**: ENG-001 (Models) and ENG-002 (Services) must be completed first

---

## ✅ Execution Plan

### Step 0: Verify Preconditions/Pre-Flight

*Ensure all necessary environment permissions, directories, files, variables, configurations, and database migrations are in place before starting.*

1. **Verify models and services modules exist** *(Est: 0.1 hours)*
   - Check models and services modules are available
   - Verify they can be imported successfully
2. **Confirm routes directory structure** *(Est: 0.1 hours)*
   - Create `gateway/src/routes/` directory if not exists
   - Verify write permissions for service user
3. **Validate existing router patterns** *(Est: 0.1 hours)*
   - Review existing `rag.py` router for consistency
   - Check app.py router registration patterns

### Implementation Steps

1. **Create routes directory and init file** *(Est: 0.2 hours)*

   ```bash
   sudo mkdir -p /opt/HX-Infrastructure-/api-gateway/gateway/src/routes
   sudo touch /opt/HX-Infrastructure-/api-gateway/gateway/src/routes/__init__.py
   ```

2. **Implement RAG upsert router** *(Est: 1.2 hours)*
   - Create `rag_upsert.py` with FastAPI router
   - Implement POST `/v1/rag/upsert` endpoint with write-scope auth
   - Add proper request/response models and validation

3. **Add comprehensive error handling** *(Est: 0.5 hours)*
   - Implement proper HTTP status codes
   - Add detailed error responses
   - Include request validation and sanitization

4. **Create security module and auth dependency** *(Est: 0.4 hours)*
   - Create `gateway/src/services/security.py` with write auth
   - Implement `require_rag_write` dependency
   - Add X-HX-Admin-Key header validation

5. **Create OpenAPI documentation** *(Est: 0.3 hours)*
   - Add endpoint descriptions and examples
   - Document request/response schemas
   - Include proper tags and metadata

---

## 🧪 Validation Criteria

### Must-Pass Validations

1. **Service Health**: Gateway service remains operational during changes
2. **End-to-End**: Routes can be imported and FastAPI router created without errors  
3. **Performance**: No impact on existing functionality
4. **Security**: Proper input validation and error handling

### Test Case

- **Description**: Create and validate RAG upsert routes with proper FastAPI integration
- **Expected Result**: Routes module exists, imports successfully, and creates valid FastAPI router

### Test Steps

1. Verify the routes file was created in correct location
2. Test Python import of the routes module
3. Validate FastAPI router instantiation
4. Check router has proper endpoints defined

### Test Commands

```bash
# Verify file creation
test -s /opt/HX-Infrastructure-/api-gateway/gateway/src/routes/rag_upsert.py && echo "✅ Routes file created."

# Test Python imports including security module
cd /opt/HX-Infrastructure-/api-gateway/gateway && python -c "from src.routes.rag_upsert import router; from src.services.security import require_rag_write; print('✅ Router and security imports successfully')"

# Check router configuration
cd /opt/HX-Infrastructure-/api-gateway/gateway && python -c "
from src.routes.rag_upsert import router
print(f'✅ Router has {len(router.routes)} routes defined')
for route in router.routes:
    print(f'  - {route.methods} {route.path}')
"

# Verify module structure
python -m pyflakes /opt/HX-Infrastructure-/api-gateway/gateway/src/routes/rag_upsert.py
```

---

## 📊 Status Tracking

- **Current Status**: `Not Started`
- **Completion**: `0%`
- **Time Estimated**: `2.7 hours`
- **Time Actual**: `[To be filled]`
- **Last Updated**: `2025-08-21`
- **Blocked By**: `ENG-001 (Models), ENG-002 (Services)`

### Change Log

- **2025-08-21**: Task created based on SOLID-compliant RAG upsert requirements

---

## 📎 Additional Information

### Requirements

- ENG-001 (Models Module) and ENG-002 (Services Module) must be completed first
- FastAPI router implementation following existing patterns
- Write-scope authentication with X-HX-Admin-Key header
- Proper OpenAPI documentation and examples
- Comprehensive error handling and validation

### Notes

- Routes layer handles HTTP concerns and delegates business logic to services
- Follows existing patterns from rag.py router
- Implements proper separation of concerns

---

## 📚 References

- **Related Issues**: RAG Document Upsert Endpoint Implementation
- **Documentation**: `/opt/HX-Infrastructure-/api-gateway/x-Tasks/RAG-Document-Upsert-Endpoint-Tasks/RAG-Doc-Upsert-2.md`
- **Architecture Notes**: SOLID principles implementation with controller layer separation
- **Dependencies**: Requires ENG-001 and ENG-002 completion, blocks ENG-004 (Router Registration)
