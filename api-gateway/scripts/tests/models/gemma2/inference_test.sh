#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - Test ONLY gemma2 inference capability
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

MODEL_NAME="llm02-gemma2-2b"

echo "💎 Testing Gemma2 Inference Performance"
echo "======================================="
echo "Model: $MODEL_NAME"
echo "Gateway: $API_BASE"
echo

# Test various inference scenarios optimized for Gemma2's capabilities
test_prompts=(
    "Summarize the key principles of effective communication"
    "Explain how blockchain technology works in simple terms"
    "Compare and contrast different programming paradigms"
    "Describe the benefits of meditation for mental health"
    "Write a brief guide on time management for students"
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
    payload=$(jq -n \
        --arg model "$MODEL_NAME" \
        --arg prompt "$prompt" \
        --argjson temperature 0.6 \
        --argjson max_tokens 200 \
        '{
            "model": $model,
            "messages": [{"role": "user", "content": $prompt}],
            "temperature": $temperature,
            "max_tokens": $max_tokens
        }')
    
    response=$(curl -sf --max-time 60 "${API_BASE}/v1/chat/completions" \
        -H "Authorization: Bearer ${AUTH_KEY}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        --data-binary "$payload" | jq -r '.choices[0].message.content // "ERROR"' 2>/dev/null)
    
    # Check if curl failed (exit code captured by bash)
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo "❌ FAIL: HTTP request failed"
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
echo "======================================="
echo "Gemma2 Inference Test Results:"
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
