#!/usr/bin/env bash
set -uo pipefail

# SOLID: Single Responsibility - Test ONLY cogito inference capability

# Preflight checks - Verify required commands are available
echo "🔍 Checking dependencies..."
for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "❌ FAIL: Required command '$cmd' not found"
        echo "   Please install $cmd to run this test"
        exit 1
    fi
done
echo "✅ Dependencies verified: curl, jq"
echo

# Configuration - Environment variables with fallbacks (SOLID: Dependency Inversion)
API_BASE="${API_BASE:-http://localhost:4000}"

# Require explicit authentication token
if [[ -z "${AUTH_TOKEN:-}" ]] && [[ -z "${MASTER_KEY:-}" ]]; then
    echo "❌ Either AUTH_TOKEN or MASTER_KEY environment variable must be set"
    echo "   Please provide authentication credentials"
    exit 1
fi

# Prefer AUTH_TOKEN if available, otherwise use MASTER_KEY
AUTH_KEY="${AUTH_TOKEN:-${MASTER_KEY}}"

MODEL_NAME="llm02-cogito-32b"

echo "🧠 Testing Cogito Inference Performance"
echo "======================================"
echo "Model: $MODEL_NAME"
echo "Gateway: $API_BASE"
echo

# Test various inference scenarios optimized for Cogito's strengths (32B model)
test_prompts=(
    "Analyze the philosophical implications of artificial consciousness"
    "Write a comprehensive business strategy for a tech startup"
    "Explain the relationship between quantum mechanics and general relativity"
    "Create a detailed technical architecture for a distributed system"
    "Solve this complex reasoning problem: If all roses are flowers, and some flowers fade quickly, what can we conclude?"
)

echo "Running inference tests..."
total_tests=${#test_prompts[@]}
passed=0

for i in "${!test_prompts[@]}"; do
    prompt="${test_prompts[$i]}"
    echo
    echo "Test $((i+1))/$total_tests: Testing inference capability"
    echo "Prompt: $(echo "$prompt" | head -c 60)..."
    
    # Create temporary file for response body
    temp_response=$(mktemp)
    
    # Capture HTTP status code and response body separately
    http_status=$(curl -s --max-time 60 -w '%{http_code}' -o "$temp_response" \
        "${API_BASE}/v1/chat/completions" \
        -H "Authorization: Bearer ${AUTH_KEY}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg model "$MODEL_NAME" --arg content "$prompt" '{
            "model": $model,
            "messages": [{"role": "user", "content": $content}],
            "temperature": 0.5,
            "max_tokens": 250
        }')")
    
    curl_exit_code=$?
    
    # Check curl command success first
    if [[ $curl_exit_code -ne 0 ]]; then
        echo "❌ FAIL: curl command failed (exit code: $curl_exit_code)"
        echo "   This could indicate network issues, timeout, or connection problems"
        rm -f "$temp_response"
        continue
    fi
    
    # Check HTTP status code
    if [[ "$http_status" != "200" ]]; then
        echo "❌ FAIL: HTTP $http_status error"
        echo "   Raw response: $(cat "$temp_response")"
        rm -f "$temp_response"
        continue
    fi
    
    # Parse JSON response safely
    response=$(jq -r '.choices[0].message.content // "ERROR"' "$temp_response" 2>/dev/null)
    jq_exit_code=$?
    
    # Clean up temporary file
    rm -f "$temp_response"
    
    # Check JSON parsing success
    if [[ $jq_exit_code -ne 0 ]]; then
        echo "❌ FAIL: Invalid JSON response from API"
        continue
    fi
    
    if [[ "$response" != "ERROR" && -n "$response" && ${#response} -gt 20 ]]; then
        echo "✅ PASS: Generated $(echo "$response" | wc -w) words"
        echo "Preview: $(echo "$response" | head -c 120)..."
        ((passed++))
    else
        echo "❌ FAIL: No valid response generated"
    fi
done

echo
echo "======================================"
echo "Cogito Inference Test Results:"
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
