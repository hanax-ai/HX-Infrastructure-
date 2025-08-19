#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY tests /v1/models endpoint
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/test_config.sh"

TEST_NAME="models_test"
log_test "$TEST_NAME" "Testing /v1/models endpoint"

# Test /v1/models endpoint
if ! response=$(make_request "/v1/models" ""); then
    log_test "$TEST_NAME" "❌ FAIL: API request failed"
    exit 1
fi

# Verify response is valid JSON
if ! echo "$response" | jq empty 2>/dev/null; then
    log_test "$TEST_NAME" "❌ FAIL: Invalid JSON response"
    exit 1
fi

# Validate response structure
model_count=$(echo "$response" | jq -r '.data | length')

if [[ "$model_count" -gt 0 ]]; then
    models=$(echo "$response" | jq -r '.data[].id' | tr '\n' ' ')
    log_test "$TEST_NAME" "✅ SUCCESS: Found $model_count models: $models"
    exit 0
else
    log_test "$TEST_NAME" "❌ FAIL: No models found in response"
    exit 1
fi
