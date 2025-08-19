#!/usr/bin/env bash
set -uo pipefail

# SOLID: Single Responsibility - Test ONLY llama3 inference capability
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

MODEL_NAME="llm01-llama3.2-3b"

echo "🧠 Testing Llama3 Inference Performance"
echo "======================================"
echo "Model: $MODEL_NAME"
echo "Gateway: $API_BASE"
echo

# Test various inference scenarios
test_prompts=(
    "Write a Python function to calculate fibonacci numbers"
    "Explain quantum computing in simple terms"
    "What are the benefits of renewable energy?"
    "Create a short poem about artificial intelligence"
    "Solve this math problem: What is 15 * 24 + 7?"
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
    local payload
    payload=$(jq -n \
        --arg model "$MODEL_NAME" \
        --arg prompt "$prompt" \
        --argjson temperature 0.3 \
        --argjson max_tokens 150 \
        '{
            "model": $model,
            "messages": [{"role": "user", "content": $prompt}],
            "temperature": $temperature,
            "max_tokens": $max_tokens
        }')
    
    response=$(curl -s --max-time 45 "${API_BASE}/v1/chat/completions" \
        -H "Authorization: Bearer ${AUTH_KEY}" \
        -H "Content-Type: application/json" \
        --data-binary "$payload" | jq -r '.choices[0].message.content // "ERROR"' 2>/dev/null)
    
    if [[ "$response" != "ERROR" && -n "$response" && ${#response} -gt 10 ]]; then
        echo "✅ PASS: Generated $(echo "$response" | wc -w) words"
        echo "Preview: $(echo "$response" | head -c 100)..."
        ((passed++))
    else
        echo "❌ FAIL: No valid response generated"
    fi
done

echo
echo "======================================="
echo "Llama3 Inference Test Results:"
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
