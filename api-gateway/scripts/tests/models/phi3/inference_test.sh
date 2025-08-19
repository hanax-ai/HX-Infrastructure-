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

# Require explicit authentication token
if [[ -z "${AUTH_TOKEN:-}" ]] && [[ -z "${HX_MASTER_KEY:-}" ]] && [[ -z "${MASTER_KEY:-}" ]]; then
    echo "❌ Either AUTH_TOKEN, HX_MASTER_KEY, or MASTER_KEY environment variable must be set"
    echo "   Please provide authentication credentials"
    exit 1
fi

# Prefer AUTH_TOKEN, then HX_MASTER_KEY, then MASTER_KEY
AUTH_KEY="${AUTH_TOKEN:-${HX_MASTER_KEY:-${MASTER_KEY}}}"

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

# Array to track temp files for cleanup
temp_files=()
# Set up cleanup trap once
cleanup_temp_files() {
    for file in "${temp_files[@]}"; do
        rm -f "$file"
    done
}
trap cleanup_temp_files EXIT

for i in "${!test_prompts[@]}"; do
    prompt="${test_prompts[$i]}"
    echo
    echo "Test $((i+1))/$total_tests: Testing inference capability"
    echo "Prompt: $(echo "$prompt" | head -c 60)..."
    
    # Build payload and send request; detect HTTP errors
    tmp_payload=$(mktemp)
    # Add to cleanup list
    temp_files+=("$tmp_payload")
    jq -n \
        --arg model "$MODEL_NAME" \
        --arg prompt "$prompt" \
        --argjson temperature 0.4 \
        --argjson max_tokens 300 \
        '{
            model: $model,
            messages: [{role: "user", content: $prompt}],
            temperature: $temperature,
            max_tokens: $max_tokens
        }' > "$tmp_payload"

    # Detect curl support for --fail-with-body (available in curl 7.76.0+)
    fail_flag="-f"
    if curl --help all 2>/dev/null | grep -q -- "--fail-with-body"; then
        fail_flag="--fail-with-body"
    fi

    # Execute curl with proper exit code capture
    raw_response=$(curl -s "${fail_flag}" -S --max-time "${TIMEOUT:-60}" "${API_BASE}/v1/chat/completions" \
        -H "Authorization: Bearer ${AUTH_KEY}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        --data-binary @"$tmp_payload" 2>&1)
    curl_exit_code=$?
    
    # Clean up temp file
    rm -f "$tmp_payload"

    # Check if curl failed
    if [[ $curl_exit_code -ne 0 ]]; then
        echo "❌ FAIL: HTTP request failed (exit code: $curl_exit_code)"
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
