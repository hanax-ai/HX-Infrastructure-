#!/usr/bin/env bash
set -euo pipefail

# Single Responsibility - ONLY tests /v1/embeddings endpoint
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/test_config.sh"

TEST_NAME="embeddings_test"
log_test "$TEST_NAME" "Testing /v1/embeddings endpoint"

# Test each embedding model with expected dimensions
check_embedding_model() {
    local model="$1"
    local expected_dim="$2"
    
    log_test "$TEST_NAME" "Testing $model (expecting $expected_dim dimensions)"
    
    local payload="{\"model\":\"$model\",\"input\":\"HX Infrastructure test\"}"
    local response actual_dim
    
    # Safely execute request and capture any failures
    set +e
    response=$(make_request "/v1/embeddings" "$payload")
    local request_rc=$?
    set -e
    
    if [[ $request_rc -ne 0 ]]; then
        log_test "$TEST_NAME" "❌ $model: Request failed"
        return 1
    fi
    
    # Safely parse JSON with exit-on-null behavior and validate numeric output
    set +e
    actual_dim=$(echo "$response" | jq -er '.data[0].embedding | length' 2>/dev/null)
    local jq_rc=$?
    set -e
    
    # Validate jq succeeded and result is a numeric integer
    if [[ $jq_rc -ne 0 ]] || [[ -z "$actual_dim" ]] || ! [[ "$actual_dim" =~ ^[0-9]+$ ]]; then
        log_test "$TEST_NAME" "❌ $model: Invalid JSON response, missing embedding data, or non-numeric dimension"
        return 1
    fi
    
    if (( actual_dim == expected_dim )); then
        log_test "$TEST_NAME" "✅ $model: $actual_dim dimensions (correct)"
        return 0
    else
        log_test "$TEST_NAME" "❌ $model: Expected $expected_dim, got $actual_dim dimensions"
        return 1
    fi
}

# Test all embedding models
failed=0
check_embedding_model "emb-premium" 1024 || ((failed++))
check_embedding_model "emb-perf" 768 || ((failed++))
check_embedding_model "emb-light" 384 || ((failed++))

if [[ $failed -eq 0 ]]; then
    log_test "$TEST_NAME" "✅ SUCCESS: All embedding models working correctly"
    exit 0
else
    log_test "$TEST_NAME" "❌ FAIL: $failed embedding model(s) failed"
    exit 1
fi
