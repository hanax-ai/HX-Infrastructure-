#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY orchestrates test execution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/test_config.sh"

SUITE_NAME="gateway_smoke_suite"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="${LOG_DIR}/gw-smoke-${TIMESTAMP}.log"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Test execution function
run_test() {
    local test_name="$1"
    local test_script="${SCRIPT_DIR}/../core/${test_name}.sh"
    
    echo "--- Testing: $test_name ---" | tee -a "${LOG_FILE}"
    
    if [[ ! -f "$test_script" ]]; then
        echo "❌ Test script not found: $test_script" | tee -a "${LOG_FILE}"
        return 1
    fi
    
    if [[ ! -x "$test_script" ]]; then
        echo "❌ Test script not executable: $test_script" | tee -a "${LOG_FILE}"
        return 1
    fi
    
    if timeout 60 "$test_script" 2>&1 | tee -a "${LOG_FILE}"; then
        echo "✅ PASS: $test_name" | tee -a "${LOG_FILE}"
        return 0
    else
        echo "❌ FAIL: $test_name" | tee -a "${LOG_FILE}"
        return 1
    fi
}

# Main execution
echo "=== Gateway Smoke Test Suite @ ${TIMESTAMP} ===" | tee "${LOG_FILE}"
echo "API Gateway: http://${GW_HOST}:${GW_PORT}" | tee -a "${LOG_FILE}"
echo "Log File: ${LOG_FILE}" | tee -a "${LOG_FILE}"
echo | tee -a "${LOG_FILE}"

# Core test execution order
declare -a tests=("models_test" "embeddings_test" "chat_test" "routing_test")
failed_tests=0

for test in "${tests[@]}"; do
    if ! run_test "$test"; then
        ((failed_tests++))
    fi
    echo | tee -a "${LOG_FILE}"
done

# Final results
echo "=== Test Suite Results ===" | tee -a "${LOG_FILE}"
echo "Total Tests: ${#tests[@]}" | tee -a "${LOG_FILE}"
echo "Failed Tests: $failed_tests" | tee -a "${LOG_FILE}"

# Calculate success rate safely
if [[ ${#tests[@]} -gt 0 ]]; then
    echo "Success Rate: $(( (${#tests[@]} - failed_tests) * 100 / ${#tests[@]} ))%" | tee -a "${LOG_FILE}"
else
    echo "Success Rate: N/A" | tee -a "${LOG_FILE}"
fi

if [[ $failed_tests -eq 0 ]]; then
    echo "🎉 ALL TESTS PASSED ✅" | tee -a "${LOG_FILE}"
    exit 0
else
    echo "⚠️  SOME TESTS FAILED ❌" | tee -a "${LOG_FILE}"
    exit 1
fi
