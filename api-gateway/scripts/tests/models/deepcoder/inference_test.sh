#!/usr/bin/env bash
set -uo pipefail

# Dependency checks - Fail fast if required tools are missing
if ! command -v curl >/dev/null 2>&1; then
    echo "Required dependency 'curl' is missing" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Required dependency 'jq' is missing" >&2
    exit 1
fi

# SOLID: Single Responsibility - Test ONLY deepcoder inference capability
# Configuration - Environment variables with fallbacks (SOLID: Dependency Inversion)
API_BASE="${API_BASE:-http://localhost:4000}"
MASTER_KEY="${MASTER_KEY:-sk-hx-dev-1234}"

MODEL_NAME="llm02-deepcoder-14b"

echo "💻 Testing DeepCoder Inference Performance"
echo "=========================================="
echo "Model: $MODEL_NAME"
echo "Gateway: $API_BASE"
echo

# Test various inference scenarios optimized for DeepCoder's coding strengths
test_prompts=(
    "Write a Python function to implement binary search"
    "Debug this JavaScript code: function add(a, b) { return a - b; }"
    "Create a REST API endpoint in Node.js for user authentication"
    "Explain the difference between async/await and Promises in JavaScript"
    "Write a SQL query to find the top 5 customers by total order value"
)

echo "Running inference tests..."
total_tests=${#test_prompts[@]}
passed=0

for i in "${!test_prompts[@]}"; do
    prompt="${test_prompts[$i]}"
    echo
    echo "Test $((i+1))/$total_tests: Testing inference capability"
    echo "Prompt: $(echo "$prompt" | head -c 60)..."
    
    # Construct JSON payload safely using jq
    local payload
    payload=$(jq -n \
        --arg model "$MODEL_NAME" \
        --arg prompt "$prompt" \
        --argjson temperature 0.3 \
        --argjson max_tokens 300 \
        '{
            "model": $model,
            "messages": [{"role": "user", "content": $prompt}],
            "temperature": $temperature,
            "max_tokens": $max_tokens
        }')
    
    # Create temporary file for response body
    temp_response="/tmp/deepcoder_resp_body.$$"
    
    # Capture HTTP status code and response body separately
    http_status=$(curl -s --max-time 60 -w "%{http_code}" -o "$temp_response" \
        "${API_BASE}/v1/chat/completions" \
        -H "Authorization: Bearer ${MASTER_KEY}" \
        -H "Content-Type: application/json" \
        --data-binary "$payload")
    
    # Validate HTTP status code first
    if [[ "$http_status" =~ ^2[0-9][0-9]$ ]]; then
        # Parse response body if HTTP status is 2xx
        response=$(jq -r '.choices[0].message.content // "ERROR"' "$temp_response" 2>/dev/null)
        
        # Validate both status and response content
        if [[ "$response" != "ERROR" && -n "$response" && ${#response} -gt 20 ]]; then
            echo "✅ PASS (HTTP $http_status): Generated $(echo "$response" | wc -w) words"
            echo "Preview: $(echo "$response" | head -c 120)..."
            ((passed++))
        else
            echo "❌ FAIL (HTTP $http_status): Invalid response content"
        fi
    else
        echo "❌ FAIL (HTTP $http_status): Bad HTTP status code"
        echo "Response body: $(cat "$temp_response" | head -c 200)..."
    fi
    
    # Clean up temporary file
    rm -f "$temp_response"
done

echo
echo "=========================================="
echo "DeepCoder Inference Test Results:"
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
