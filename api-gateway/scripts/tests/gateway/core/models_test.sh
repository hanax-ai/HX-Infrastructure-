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
    # Sanitize response for safe logging: normalize to single line and remove control chars
    sanitized_response="${response}"
    # Replace newlines and carriage returns with spaces
    sanitized_response="${sanitized_response//$'\n'/ }"
    sanitized_response="${sanitized_response//$'\r'/ }"
    # Remove non-printable control characters (keep basic printable ASCII 32-126 and tab)
    sanitized_response=$(echo "$sanitized_response" | tr -cd '[:print:]\t' | tr -s ' ')
    
    # Truncate sanitized response if very large (limit to 500 chars for readability)
    response_preview="${sanitized_response:0:500}"
    if [[ ${#sanitized_response} -gt 500 ]]; then
        response_preview="${response_preview}... [truncated, ${#sanitized_response} total chars]"
    fi
    log_test "$TEST_NAME" "❌ FAIL: Invalid JSON response. Raw response: $response_preview"
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
