#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY tests /v1/chat/completions endpoint
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/test_config.sh"

TEST_NAME="chat_test"
log_test "$TEST_NAME" "Testing /v1/chat/completions endpoint"

# Test deterministic chat response
test_chat_model() {
    local model="$1"
    
    log_test "$TEST_NAME" "Testing chat with $model"
    
    local payload="{
        \"model\":\"$model\",
        \"messages\":[{\"role\":\"user\",\"content\":\"Return exactly the text: HX-OK\"}],
        \"max_tokens\":${MAX_TOKENS},
        \"temperature\":${TEMPERATURE}
    }"
    
    local response content
    
    if ! response=$(make_request "/v1/chat/completions" "$payload"); then
        log_test "$TEST_NAME" "❌ $model: Request failed"
        return 1
    fi
    
    if ! content=$(echo "$response" | jq -e -r '.choices[0].message.content' 2>/dev/null); then
        log_test "$TEST_NAME" "❌ $model: Invalid JSON response or missing content"
        return 1
    fi
    
    if [[ "$content" == "HX-OK" ]]; then
        log_test "$TEST_NAME" "✅ $model: Response contains expected text"
        return 0
    else
        log_test "$TEST_NAME" "❌ $model: Expected 'HX-OK', got: $content"
        return 1
    fi
}

# Test primary chat model
if test_chat_model "hx-chat"; then
    log_test "$TEST_NAME" "✅ SUCCESS: Chat completions working correctly"
    exit 0
else
    log_test "$TEST_NAME" "❌ FAIL: Chat completions test failed"
    exit 1
fi
