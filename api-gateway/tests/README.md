# RAG System Test Suite

This directory contains comprehensive automated tests for the RAG system that replicate all the manual validation tests we performed during the OpenAPI crisis resolution.

## Test Files

### Core Functionality Tests

- **`test_route_delete.py`** - Tests all delete operations (by IDs, namespace, filter, single document)
- **`test_route_content_loader.py`** - Tests markdown and PDF content processing 
- **`test_rag_integration.py`** - End-to-end integration tests covering complete workflows
- **`test_route_upsert.py`** - Existing upsert functionality tests
- **`test_helpers.py`** - Helper function validation tests
- **`test_models.py`** - Pydantic model validation tests

### Test Runner

- **`run_rag_tests.sh`** - Comprehensive test runner script with colored output and validation checklist

## Manual Test Validation Mapping

The automated tests directly replicate the manual validation we performed:

| Manual Test | Automated Test | Description |
|-------------|----------------|-------------|
| `curl http://127.0.0.1:4010/openapi.json` | `test_openapi_generation` | Validates OpenAPI JSON generation |
| `curl http://127.0.0.1:4010/healthz` | `test_health_endpoint` | Health endpoint validation |
| Markdown upsert with admin key | `test_upsert_markdown_success` | Content processing validation |
| Delete by IDs with real ID | `test_delete_by_ids_success` | ID-based deletion |
| Delete by namespace | `test_delete_by_namespace_success` | Namespace deletion |
| Delete by filter | `test_delete_by_filter_success` | Filter-based deletion |
| Single document delete | `test_delete_document_success` | Query parameter deletion |
| 401 without admin key | `test_*_requires_auth` | Authentication validation |
| 502/422 error handling | `test_*_error` scenarios | Error response validation |

## Critical Issue Resolution Validation

These tests specifically validate the fixes for the **OpenAPI generation crisis**:

### Before Fix (BROKEN):
- ❌ `curl -s http://127.0.0.1:4010/openapi.json` returned "Internal Server Error"
- ❌ Pydantic v2 incompatibility with `from __future__ import annotations`
- ❌ `Body(...)` vs `Query(...)` parameter confusion causing 500 errors

### After Fix (WORKING):
- ✅ `test_openapi_generation` validates successful JSON generation
- ✅ All endpoints properly documented in OpenAPI schema
- ✅ No postponed annotations in route files
- ✅ Explicit `Body(...)` parameters for complex request models
- ✅ Proper FastAPI + Pydantic v2 compatibility

## Running Tests

### Local Execution
```bash
# Run all RAG tests with the test runner
cd /opt/HX-Infrastructure-/api-gateway/tests
./run_rag_tests.sh

# Run specific test categories
cd /opt/HX-Infrastructure-/api-gateway/gateway
source venv/bin/activate

# Delete operations
python -m pytest ../tests/test_route_delete.py -v

# Content loading  
python -m pytest ../tests/test_route_content_loader.py -v

# Integration workflows
python -m pytest ../tests/test_rag_integration.py -v
```

### CI/CD Integration
The tests are integrated into the CI/CD pipeline via:
- **GitHub Actions**: `.github/workflows/rag-system-tests.yml`
- **Automated on**: Push to main/develop, PRs affecting api-gateway
- **Includes**: Qdrant service container, full environment setup, validation reports

## Environment Requirements

### Test Environment Variables
```bash
RAG_WRITE_KEY=test-admin-key
HX_ADMIN_KEY=test-admin-key  
EMBEDDING_MODEL=emb-premium
EMBEDDING_DIM=1024
QDRANT_URL=http://test-qdrant:6333
QDRANT_COLLECTION=test_collection
```

### Dependencies
- Python 3.12+
- FastAPI
- Pydantic v2+
- pytest
- httpx
- Qdrant (for integration tests)

## Test Architecture

### Mocking Strategy
- **Document Processing**: Mocked to return predictable chunks
- **Embedding Service**: Mocked to return test vectors
- **Qdrant Operations**: Mocked for unit tests, real service for integration
- **Authentication**: Environment-based test keys

### Response Validation
All tests validate:
- ✅ **Status Codes**: 200 for success, 401 for auth, 422 for validation
- ✅ **Response Format**: Consistent JSON structure across endpoints
- ✅ **Field Types**: Proper data types for all response fields
- ✅ **Business Logic**: Correct upsert counts, deletion confirmations

### Error Scenarios
Comprehensive error testing includes:
- ❌ **Authentication Failures**: Missing/invalid admin keys
- ❌ **Validation Errors**: Empty fields, invalid parameters
- ❌ **Processing Errors**: Document parsing failures
- ❌ **Service Errors**: Embedding/Qdrant service failures
- ❌ **Content Errors**: Invalid file types, empty uploads

## Production Readiness Validation

These tests confirm the system is ready for production by validating:

1. **✅ Core Functionality**: All CRUD operations working
2. **✅ Security**: Proper authentication and authorization  
3. **✅ Error Handling**: Graceful error responses and recovery
4. **✅ API Documentation**: OpenAPI schema generation functional
5. **✅ Data Integrity**: Consistent response formats and types
6. **✅ Integration**: End-to-end workflows complete successfully

The test suite provides confidence that the OpenAPI crisis has been fully resolved and the RAG system is stable for production deployment.
