#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - Test ONLY qwen3 inference capability
# Configuration - Environment variables with fallbacks (SOLID: Dependency Inversion)
API_BASE="${API_BASE:-http://localhost:4000}"

# Dependencies preflight
for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Missing dependency: $cmd"
        exit 2
    fi
done

# Require explicit authentication token
if [[ -z "${MASTER_KEY:-}" ]]; then
    echo "❌ MASTER_KEY environment variable must be set"
    echo "   Please provide authentication credentials"
    exit 1
fi

MODEL_NAME="llm01-qwen3-1.7b"

echo "🧠 Testing Qwen3 Inference Performance"
echo "====================================="
echo "Model: $MODEL_NAME"
echo "Gateway: $API_BASE"
echo

# Test various inference scenarios optimized for Qwen3's strengths
test_prompts=(
    "Translate this to Chinese: Hello, how are you today?"
    "Write a simple algorithm explanation"
    "What is machine learning?"
    "Create a haiku about technology"
    "Calculate: 45 / 9 + 12 * 3"
)

echo "Running inference tests..."
total_tests=${#test_prompts[@]}
passed=0

for i in "${!test_prompts[@]}"; do
    prompt="${test_prompts[$i]}"
    echo
    echo "Test $((i+1))/$total_tests: Testing inference capability"
    echo "Prompt: $(echo "$prompt" | head -c 50)..."
    
    payload=$(jq -n \
        --arg model "$MODEL_NAME" \
        --arg prompt "$prompt" \
        --argjson temperature 0.2 \
        --argjson max_tokens 120 \
        '{model:$model, messages:[{role:"user", content:$prompt}], temperature:$temperature, max_tokens:$max_tokens}')
    response=$(curl -s --max-time 35 "${API_BASE}/v1/chat/completions" \
        -H "Authorization: Bearer ${MASTER_KEY}" \
        -H "Content-Type: application/json" \
        --data-binary "$payload" \
      | jq -r '.choices[0].message.content // "ERROR"' 2>/dev/null)
    
    if [[ "$response" != "ERROR" && -n "$response" && ${#response} -gt 5 ]]; then
        echo "✅ PASS: Generated $(echo "$response" | wc -w) words"
        echo "Preview: $(echo "$response" | head -c 80)..."
        ((passed++))
    else
        echo "❌ FAIL: No valid response generated"
    fi
done

echo
echo "====================================="
echo "Qwen3 Inference Test Results:"
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
