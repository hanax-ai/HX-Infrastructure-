#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY tests model routing functionality
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/test_config.sh"

TEST_NAME="routing_test"
log_test "$TEST_NAME" "Testing model routing across backends"

# Models to test routing for (covering all backend servers)
declare -a routing_models=(
    "llm01-llama3.2-3b"    # LLM-01 server
    "llm02-phi3"           # LLM-02 server  
    "llm02-gemma2-2b"      # LLM-02 server
    "hx-chat"              # Load balancer group
)

test_model_routing() {
    local model="$1"
    
    log_test "$TEST_NAME" "Testing routing for $model"
    
    local payload
    payload=$(jq -n \
        --arg model "$model" \
        --arg content "Return exactly the text: HX-OK" \
        --argjson max_tokens "$MAX_TOKENS" \
        --argjson temperature "$TEMPERATURE" \
        '{
            "model": $model,
            "messages": [{"role": "user", "content": $content}],
            "max_tokens": $max_tokens,
            "temperature": $temperature
        }')
    
    local response=$(make_request "/v1/chat/completions" "$payload")
    local content
    
    if content=$(echo "$response" | jq -r '.choices[0].message.content' 2>/dev/null); then
        if echo "$content" | grep -q "HX-OK"; then
            log_test "$TEST_NAME" "✅ $model: Routing successful"
            return 0
        else
            log_test "$TEST_NAME" "❌ $model: Routing failed - got: $content"
            return 1
        fi
    else
        log_test "$TEST_NAME" "❌ $model: Invalid JSON response or missing content"
        return 1
    fi
}

# Test routing for all models
failed=0
for model in "${routing_models[@]}"; do
    test_model_routing "$model" || ((failed++))
done

if [[ $failed -eq 0 ]]; then
    log_test "$TEST_NAME" "✅ SUCCESS: All model routing working correctly"
    exit 0
else
    log_test "$TEST_NAME" "❌ FAIL: $failed model routing(s) failed"
    exit 1
fi
