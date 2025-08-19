#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - Test ONLY dolphin3 inference capability
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

MODEL_NAME="llm02-dolphin3-8b"

echo "🐬 Testing Dolphin3 Inference Performance"
echo "========================================="
echo "Model: $MODEL_NAME"
echo "Gateway: $API_BASE"
echo

# Test various inference scenarios optimized for Dolphin3's general capabilities
test_prompts=(
    "Explain the concept of machine learning in simple terms"
    "Write a creative short story about a robot discovering emotions"
    "Analyze the pros and cons of renewable energy sources"
    "Describe the process of photosynthesis step by step"
    "Create a meal plan for a vegetarian athlete"
)

echo "Running inference tests..."
total_tests=${#test_prompts[@]}
passed=0

for i in "${!test_prompts[@]}"; do
    prompt="${test_prompts[$i]}"
    echo
    echo "Test $((i+1))/$total_tests: Testing inference capability"
    echo "Prompt: $(echo "$prompt" | head -c 60)..."
    
    # Capture raw response for error extraction
    raw_response=$(jq -n --arg model "$MODEL_NAME" --arg prompt "$prompt" --argjson temp 0.7 --argjson max 250 \
        '{model:$model,messages:[{role:"user",content:$prompt}],temperature:$temp,max_tokens:$max}' | \
        curl -s -fS --max-time 60 "${API_BASE}/v1/chat/completions" \
        -H "Authorization: Bearer ${MASTER_KEY}" \
        -H "Content-Type: application/json" \
        -d @-)
    
    # Check if curl failed
    if [[ ${PIPESTATUS[1]} -ne 0 ]]; then
        echo "❌ FAIL: HTTP request failed"
        continue
    fi
    
    # Extract response content
    response=$(echo "$raw_response" | jq -r '.choices[0].message.content // "ERROR"' 2>/dev/null)
    
    if [[ "$response" != "ERROR" && -n "$response" && ${#response} -gt 20 ]]; then
        echo "✅ PASS: Generated $(echo "$response" | wc -w) words"
        echo "Preview: $(echo "$response" | head -c 120)..."
        ((passed++))
    else
        # Extract API error message for debugging
        api_error=$(echo "$raw_response" | jq -r '.error.message // ""' 2>/dev/null)
        if [[ -n "$api_error" ]]; then
            echo "API Error: $api_error"
        fi
        echo "❌ FAIL: No valid response generated"
    fi
done

echo
echo "========================================="
echo "Dolphin3 Inference Test Results:"
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
