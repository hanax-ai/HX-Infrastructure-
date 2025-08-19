#!/usr/bin/env bash
set -uo pipefail

# Dependency check - Fail fast if required tools are missing
missing_tools=()
for tool in curl jq; do
    if ! command -v "$tool" &>/dev/null; then
        missing_tools+=("$tool")
    fi
done

if [[ ${#missing_tools[@]} -gt 0 ]]; then
    echo "❌ ERROR: Missing required tools: ${missing_tools[*]}" >&2
    echo "   Please install the missing tools to run this test" >&2
    exit 1
fi

# SOLID: Single Responsibility - Test ONLY mistral inference capability
# Configuration - Environment variables with fallbacks (SOLID: Dependency Inversion)
API_BASE="${API_BASE:-http://localhost:4000}"

# Optional: Source environment file if it exists
if [[ -f "$(dirname "$0")/../../.env" ]]; then
    # shellcheck disable=SC1091
    source "$(dirname "$0")/../../.env"
fi

# Require MASTER_KEY to be set externally - fail fast if missing
if [[ -z "${MASTER_KEY:-}" ]]; then
    echo "❌ ERROR: MASTER_KEY environment variable must be set" >&2
    echo "   Please export MASTER_KEY=your_api_key or source a .env file" >&2
    exit 1
fi

MODEL_NAME="llm01-mistral-small3.2"

echo "🧠 Testing Mistral Inference Performance"
echo "======================================="
echo "Model: $MODEL_NAME"
echo "Gateway: $API_BASE"
echo

# Test various inference scenarios optimized for Mistral's strengths
test_prompts=(
    "Explain the concept of neural networks"
    "Write a JavaScript function to sort an array"
    "What are the principles of good software design?"
    "Create a professional email template"
    "Analyze this problem: How to optimize database queries?"
)

echo "Running inference tests..."
total_tests=${#test_prompts[@]}
passed=0

for i in "${!test_prompts[@]}"; do
    prompt="${test_prompts[$i]}"
    echo
    echo "Test $((i+1))/$total_tests: Testing inference capability"
    echo "Prompt: $(echo "$prompt" | head -c 50)..."
    
    # Construct JSON payload safely using jq
    payload=$(jq -n \
        --arg model "$MODEL_NAME" \
        --arg prompt "$prompt" \
        --argjson temperature 0.4 \
        --argjson max_tokens 200 \
        '{
            "model": $model,
            "messages": [{"role": "user", "content": $prompt}],
            "temperature": $temperature,
            "max_tokens": $max_tokens
        }')
    
    # Capture both response body and HTTP status
    response_body=$(mktemp)
    http_status=$(curl -sS --max-time 50 -w "%{http_code}" -o "$response_body" \
        "${API_BASE}/v1/chat/completions" \
        -H "Authorization: Bearer ${MASTER_KEY}" \
        -H "Content-Type: application/json" \
        --data-binary "$payload")
    
    if [[ "$http_status" == "200" ]]; then
        response=$(jq -r '.choices[0].message.content // "ERROR"' "$response_body" 2>/dev/null)
    else
        echo "❌ HTTP Error: $http_status"
        response="ERROR"
    fi
    
    rm -f "$response_body"
    
    if [[ "$http_status" -eq 200 && "$response" != "ERROR" && -n "$response" && ${#response} -gt 15 ]]; then
        echo "✅ PASS: Generated $(echo "$response" | wc -w) words"
        echo "Preview: $(echo "$response" | head -c 100)..."
        ((passed++))
    else
        echo "❌ FAIL: No valid response generated (HTTP status: $http_status)"
    fi
done

echo
echo "======================================="
echo "Mistral Inference Test Results:"
echo "Total Tests: $total_tests"
echo "Passed: $passed"
echo "Failed: $((total_tests - passed))"

if [[ $passed -eq $total_tests ]]; then
    echo "✅ SUCCESS: All inference tests passed!"
    exit 0
else
    echo "❌ FAIL: Some inference tests failed!"
    exit 1
fi
