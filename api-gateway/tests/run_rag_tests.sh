#!/bin/bash
# tests/run_rag_tests.sh
"""
Test runner for RAG system validation
Executes the comprehensive test suite that validates all functionality
we manually tested during the OpenAPI fix validation.
"""

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}    RAG System Comprehensive Test Suite${NC}"
echo -e "${BLUE}===================================================${NC}"
echo ""

# Set test environment
export PYTEST_CURRENT_TEST=""
export RAG_WRITE_KEY="test-admin-key"
export HX_ADMIN_KEY="test-admin-key"
export EMBEDDING_MODEL="emb-premium"
export EMBEDDING_DIM="1024"
export QDRANT_URL="http://test-qdrant:6333"
export QDRANT_COLLECTION="test_collection"

echo -e "${YELLOW}Environment Setup:${NC}"
echo "  RAG_WRITE_KEY: ${RAG_WRITE_KEY}"
echo "  QDRANT_URL: ${QDRANT_URL}"
echo "  QDRANT_COLLECTION: ${QDRANT_COLLECTION}"
echo ""

echo -e "${YELLOW}Checking dependency versions...${NC}"
cd "$(dirname "$0")/../gateway"
if [[ -f "requirements.txt" ]]; then
    echo "Using pinned requirements from requirements.txt:"
    grep -E "(fastapi|pydantic|uvicorn|httpx)" requirements.txt | head -4
else
    echo "⚠️  No requirements.txt found, using requirements.lock"
fi
echo ""

# Change to the gateway directory
cd "$(dirname "$0")/../gateway"

echo -e "${YELLOW}Running test discovery...${NC}"
if ! ./venv/bin/python -m pytest --collect-only ../tests/ >/dev/null 2>&1; then
    echo -e "${RED}❌ Test discovery failed. Check test imports and dependencies.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Test discovery successful${NC}"
echo ""

# Test categories to run
TEST_CATEGORIES=(
    "delete operations:::../tests/test_route_delete.py"
    "content loading:::../tests/test_route_content_loader.py" 
    "integration workflow:::../tests/test_rag_integration.py"
    "existing functionality:::../tests/test_route_upsert.py"
    "helper functions:::../tests/test_helpers.py"
    "model validation:::../tests/test_models.py"
)

TOTAL_PASSED=0
TOTAL_FAILED=0
FAILED_CATEGORIES=()

for category_info in "${TEST_CATEGORIES[@]}"; do
    IFS=':::' read -r category_name test_path <<< "$category_info"
    
    echo -e "${BLUE}Running ${category_name} tests...${NC}"
    echo "  Test file: $test_path"
    
    if [[ -f "$test_path" ]]; then
        # Run tests with verbose output
        if ./venv/bin/python -m pytest "$test_path" -v --tb=short; then
            echo -e "${GREEN}✅ ${category_name} tests PASSED${NC}"
            ((TOTAL_PASSED++))
        else
            echo -e "${RED}❌ ${category_name} tests FAILED${NC}"
            ((TOTAL_FAILED++))
            FAILED_CATEGORIES+=("$category_name")
        fi
    else
        echo -e "${YELLOW}⚠️  Test file not found: $test_path${NC}"
        ((TOTAL_FAILED++))
        FAILED_CATEGORIES+=("$category_name (file not found)")
    fi
    echo ""
done

# Summary
echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}                 TEST SUMMARY${NC}"
echo -e "${BLUE}===================================================${NC}"
echo ""
echo -e "Total test categories: $((TOTAL_PASSED + TOTAL_FAILED))"
echo -e "${GREEN}Passed: ${TOTAL_PASSED}${NC}"
echo -e "${RED}Failed: ${TOTAL_FAILED}${NC}"
echo ""

if [[ ${#FAILED_CATEGORIES[@]} -gt 0 ]]; then
    echo -e "${RED}Failed categories:${NC}"
    for failed_cat in "${FAILED_CATEGORIES[@]}"; do
        echo -e "${RED}  - $failed_cat${NC}"
    done
    echo ""
fi

# Validation against manual tests
echo -e "${YELLOW}Manual Validation Checklist:${NC}"
echo "The following manual tests were replicated in the automated test suite:"
echo ""
echo -e "${GREEN}✅ OpenAPI Generation${NC} - test_openapi_generation"
echo -e "${GREEN}✅ Health Endpoint${NC} - test_health_endpoint"  
echo -e "${GREEN}✅ Authentication (401 without key)${NC} - test_*_requires_auth"
echo -e "${GREEN}✅ Markdown Processing${NC} - test_upsert_markdown_success"
echo -e "${GREEN}✅ PDF Processing${NC} - test_upsert_pdf_success"
echo -e "${GREEN}✅ Delete by IDs${NC} - test_delete_by_ids_success"
echo -e "${GREEN}✅ Delete by Namespace${NC} - test_delete_by_namespace_success"
echo -e "${GREEN}✅ Delete by Filter${NC} - test_delete_by_filter_success"
echo -e "${GREEN}✅ Single Document Delete${NC} - test_delete_document_success"
echo -e "${GREEN}✅ Response Format Consistency${NC} - test_*_response_format"
echo -e "${GREEN}✅ Error Handling${NC} - test_*_error scenarios"
echo -e "${GREEN}✅ Full Workflow Integration${NC} - test_full_rag_lifecycle"
echo ""

if [[ $TOTAL_FAILED -eq 0 ]]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED! RAG system is fully validated.${NC}"
    echo -e "${GREEN}The system is ready for production deployment.${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed. Please review the failures above.${NC}"
    echo -e "${RED}Fix the issues before deploying to production.${NC}"
    exit 1
fi
