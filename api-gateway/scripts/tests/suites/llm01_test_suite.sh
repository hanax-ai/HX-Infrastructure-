#!/usr/bin/env bash
set -uo pipefail

# Source shared environment configuration if available
SHARED_ENV_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../gateway/config/smoke_suite.sh"
if [[ -f "$SHARED_ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SHARED_ENV_FILE"
fi

# SOLID: Single Responsibility - ONLY orchestrates model tests, doesn't test itself
echo "🧪 HX-Infrastructure API Gateway - LLM-01 Test Suite"
echo "===================================================="
echo "Date: $(date)"
echo

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# SOLID: Single Responsibility - Function only runs one test
run_test() {
    local test_script="$1"
    local test_name="$2"
    
    echo -e "${BLUE}[RUNNING]${NC} $test_name"
    ((TESTS_TOTAL++))
    
    # Respect VERBOSE flag - show output if VERBOSE=1, otherwise suppress
    local exit_status
    if [[ "${VERBOSE:-0}" == "1" ]]; then
        bash "$test_script"
        exit_status=$?
    else
        bash "$test_script" >/dev/null 2>&1
        exit_status=$?
    fi
    
    # Use captured exit status to determine PASS/FAIL
    if [[ $exit_status -eq 0 ]]; then
        echo -e "${GREEN}[PASS]${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}[FAIL]${NC} $test_name"
        ((TESTS_FAILED++))
    fi
    echo
}

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Testing LLM-01 Models via API Gateway..."
echo "========================================"

# SOLID: Open/Closed - Easy to add new models without changing orchestration logic
run_test "$SCRIPT_DIR/../models/llama3/availability_test.sh" "Llama3 Availability"
run_test "$SCRIPT_DIR/../models/llama3/basic_chat_test.sh" "Llama3 Basic Chat"

run_test "$SCRIPT_DIR/../models/qwen3/availability_test.sh" "Qwen3 Availability"
run_test "$SCRIPT_DIR/../models/qwen3/basic_chat_test.sh" "Qwen3 Basic Chat"

run_test "$SCRIPT_DIR/../models/mistral/availability_test.sh" "Mistral Availability"
run_test "$SCRIPT_DIR/../models/mistral/basic_chat_test.sh" "Mistral Basic Chat"
run_test "$SCRIPT_DIR/../models/mistral/inference_test.sh" "Mistral Inference"

# Results summary
echo "========================================="
echo "Test Results Summary:"
echo "Total Tests: $TESTS_TOTAL"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed!${NC}"
    exit 1
fi
