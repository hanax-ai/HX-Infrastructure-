#!/usr/bin/env bash
set -uo pipefail

# Dependency checks - Verify required binaries before running tests
if ! command -v curl >/dev/null 2>&1; then
    echo "Error: Required dependency 'curl' is missing" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: Required dependency 'jq' is missing" >&2
    exit 1
fi

# SOLID: Single Responsibility - Test ONLY phi3 inference capability
# Configuration - Environment variables with fallbacks (SOLID: Dependency Inversion)
API_BASE="${API_BASE:-http://localhost:4000}"

# Validate required authentication
if [[ -z "${MASTER_KEY:-}" ]]; then
    echo "ERROR: MASTER_KEY environment variable is required" >&2
    exit 1
fi

MODEL_NAME="llm02-phi3"

echo "⚡ Testing Phi3 Inference Performance"
echo "===================================="
echo "Model: $MODEL_NAME"
echo "Gateway: $API_BASE"
echo

# Test various inference scenarios optimized for Phi3's reasoning capabilities
test_prompts=(
    "Solve this logic puzzle: Three friends have different favorite colors and pets"
    "Explain the scientific method and its importance in research"
    "Calculate the compound interest on \$1000 at 5% annually for 3 years"
    "Describe the water cycle and its impact on climate patterns"
    "Write a persuasive argument for the importance of reading books"
)

echo "Running inference tests..."
total_tests=${#test_prompts[@]}
passed=0

for i in "${!test_prompts[@]}"; do
    prompt="${test_prompts[$i]}"
    echo
    echo "Test $((i+1))/$total_tests: Testing inference capability"
    echo "Prompt: $(echo "$prompt" | head -c 60)..."
    
    # Build payload and send request; detect HTTP errors
    raw_response=$(jq -n \
        --arg model "$MODEL_NAME" \
        --arg prompt "$prompt" \
        --argjson temperature 0.4 \
        --argjson max_tokens 300 \
        '{
            model: $model,
            messages: [{role: "user", content: $prompt}],
            temperature: $temperature,
            max_tokens: $max_tokens
        }' | \
        curl -s -fS --max-time "${TIMEOUT:-60}" "${API_BASE}/v1/chat/completions" \
        -H "Authorization: Bearer ${MASTER_KEY}" \
        -H "Content-Type: application/json" \
        -d @-)

    # Check if curl failed
    if [[ ${PIPESTATUS[1]} -ne 0 ]]; then
        echo "❌ FAIL: HTTP request failed"
        continue
    fi

    response=$(echo "$raw_response" | jq -r '.choices[0].message.content // "ERROR"' 2>/dev/null)
    
    if [[ "$response" != "ERROR" && -n "$response" && ${#response} -gt 20 ]]; then
        echo "✅ PASS: Generated $(echo "$response" | wc -w) words"
        echo "Preview: $(echo "$response" | head -c 120)..."
        ((passed++))
    else
        echo "❌ FAIL: No valid response generated"
    fi
done

echo
echo "===================================="
echo "Phi3 Inference Test Results:"
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
