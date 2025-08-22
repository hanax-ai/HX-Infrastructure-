# Engineering Task: Implement RAG Upsert Services Module

> **Task ID**: `ENG-002`  
> **Priority**: `High`  
> **Assigned To**: `Infrastructure Team`  
> **Due Date**: `2025-08-21`

---

## 🎯 Objective

Create a dedicated services module for RAG upsert business logic, implementing the service layer of the SOLID architecture to handle document processing and vector operations.

---

## 🏗️ Infrastructure Context

- **Component**: `api-gateway`
- **Service Impact**: `hx-gateway-ml.service (port 4010)`
- **Network Changes**: `No`
- **Rollback Plan**: `Delete the created services module and revert any imports`

---

## ⚠️ Risk Assessment

- **Risk Level**: `Low`
- **Potential Impact**: New service module creation with business logic isolation
- **Mitigation**: Comprehensive unit testing and validation before route integration
- **Dependencies**: ENG-001 (Models Module) must be completed first

---

## ✅ Execution Plan

### Step 0: Verify Preconditions/Pre-Flight

*Ensure all necessary environment permissions, directories, files, variables, configurations, and database migrations are in place before starting.*

1. **Verify models module exists** *(Est: 0.1 hours)*
   - Check `/opt/HX-Infrastructure-/api-gateway/gateway/src/models/rag_upsert_models.py` exists
   - Verify models can be imported successfully
2. **Confirm services directory structure** *(Est: 0.1 hours)*
   - Create `gateway/src/services/` directory if not exists
   - Verify write permissions for service user
3. **Validate Qdrant connection** *(Est: 0.1 hours)*
   - Test Qdrant client connectivity
   - Verify collection `hx_rag_default` exists

### Implementation Steps

1. **Create services directory and init file** *(Est: 0.2 hours)*

   ```bash
   sudo mkdir -p /opt/HX-Infrastructure-/api-gateway/gateway/src/services
   sudo touch /opt/HX-Infrastructure-/api-gateway/gateway/src/services/__init__.py
   ```

2. **Implement RAG upsert service class** *(Est: 1.0 hours)*
   - Create `rag_upsert_service.py` with service class
   - Implement document validation with 1024-dimensional guard
   - Add namespace keyword validation and schema hygiene

3. **Add vector processing logic** *(Est: 0.8 hours)*
   - Implement embedding generation via LiteLLM with telemetry
   - Add batch processing for multiple documents
   - Include error handling and retries

4. **Implement Qdrant operations** *(Est: 0.6 hours)*
   - Add vector upsert with proper metadata and telemetry
   - Implement namespace-based point IDs with idempotency (stable hash)
   - Add collection validation and health checks

5. **Add minimal telemetry logging** *(Est: 0.3 hours)*
   - Wrap external I/O with timing and status logs
   - Log embedding generation and Qdrant operations
   - Include structured logging for operational visibility

---

## 🧪 Validation Criteria

### Must-Pass Validations

1. **Service Health**: Gateway service remains operational during changes
2. **End-to-End**: Service can be imported and instantiated without errors  
3. **Performance**: No impact on existing functionality
4. **Security**: Proper error handling and input validation

### Test Case

- **Description**: Create and validate RAG upsert service with proper business logic separation
- **Expected Result**: Service module exists, imports successfully, and can process documents

### Test Steps

1. Verify the service file was created in correct location
2. Test Python import of the service module
3. Validate service instantiation and method calls
4. Test embedding generation and vector operations

### Test Commands

```bash
# Verify file creation
test -s /opt/HX-Infrastructure-/api-gateway/gateway/src/services/rag_upsert_service.py && echo "✅ Service file created."

# Test Python imports
cd /opt/HX-Infrastructure-/api-gateway/gateway && python -c "from src.services.rag_upsert_service import RagUpsertService; print('✅ Service imports successfully')"

# Check service instantiation with telemetry
cd /opt/HX-Infrastructure-/api-gateway/gateway && python -c "
from src.services.rag_upsert_service import RagUpsertService
service = RagUpsertService()
print('✅ Service instantiated successfully')
"

# Test telemetry logging setup
cd /opt/HX-Infrastructure-/api-gateway/gateway && python -c "
import logging
log = logging.getLogger('rag')
log.info('✅ Telemetry logging configured')
"

# Verify module structure
python -m pyflakes /opt/HX-Infrastructure-/api-gateway/gateway/src/services/rag_upsert_service.py
```

---

## 📊 Status Tracking

- **Current Status**: `Not Started`
- **Completion**: `0%`
- **Time Estimated**: `3.1 hours`
- **Time Actual**: `[To be filled]`
- **Last Updated**: `2025-08-21`
- **Blocked By**: `ENG-001 (Models Module)`

### Change Log

- **2025-08-21**: Task created based on SOLID-compliant RAG upsert requirements

---

## 📎 Additional Information

### Requirements

- ENG-001 (Models Module) must be completed first
- Working Qdrant connection to hx_rag_default collection
- LiteLLM authentication properly configured
- 1024-dimensional embedding validation
- Stable hash-based point IDs for idempotency
- Minimal telemetry for operational visibility

### Notes

- Service layer handles all business logic for document processing
- Implements proper error handling and validation
- Includes dimension guards as specified in hardening requirements

---

## 📚 References

- **Related Issues**: RAG Document Upsert Endpoint Implementation
- **Documentation**: `/opt/HX-Infrastructure-/api-gateway/x-Tasks/RAG-Document-Upsert-Endpoint-Tasks/RAG-Doc-Upsert-1.md`
- **Architecture Notes**: SOLID principles implementation with service layer separation
- **Dependencies**: Requires ENG-001 completion, blocks ENG-003 (Routes Module)
