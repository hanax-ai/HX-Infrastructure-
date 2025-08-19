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
if [[ -z "${AUTH_TOKEN:-}" ]] && [[ -z "${HX_MASTER_KEY:-}" ]] && [[ -z "${MASTER_KEY:-}" ]]; then
    echo "❌ Either AUTH_TOKEN, HX_MASTER_KEY, or MASTER_KEY environment variable must be set"
    echo "   Please provide authentication credentials"
    exit 1
fi

# Prefer AUTH_TOKEN, then HX_MASTER_KEY, then MASTER_KEY
AUTH_KEY="${AUTH_TOKEN:-${HX_MASTER_KEY:-${MASTER_KEY}}}"

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
    
    # Capture both response body and HTTP status code with proper error handling
    set +e  # Temporarily disable exit on error to capture curl's exit status
    curl_output=$(curl -sS --max-time "${TIMEOUT:-35}" "${API_BASE}/v1/chat/completions" \
        -H "Authorization: Bearer ${AUTH_KEY}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        --data-binary "$payload" \
        -w "\n%{http_code}")
    CURL_EXIT=$?
    set -e  # Re-enable exit on error
    
    # Handle transport errors separately from HTTP errors
    if [[ $CURL_EXIT -ne 0 ]]; then
        echo "❌ FAIL: Transport error - curl failed with exit code $CURL_EXIT"
        echo "   This indicates network connectivity or timeout issues"
        http_code="000"  # Set clear indicator for transport failure
        response="TRANSPORT_ERROR"
    else
        # Split response body and HTTP status using shell parameter expansion
        http_code="${curl_output##*$'\n'}"  # Extract last line (HTTP code)
        body="${curl_output%$'\n'*}"        # Extract everything except last line
        
        # Validate http_code is a 3-digit number
        case "$http_code" in
            [0-9][0-9][0-9])
                # Valid 3-digit HTTP code, parse response body with jq
                response=$(echo "$body" | jq -r '.choices[0].message.content // "ERROR"' 2>/dev/null)
                ;;
            *)
                # Invalid HTTP code format, set error sentinel
                response="ERROR"
                http_code="000"
                ;;
        esac
    fi
    
    # Configurable minimum response length (default 2 to accommodate minimal valid outputs like "OK.")
    min_response_length="${MIN_RESP_LEN:-2}"
    
    if [[ "$response" != "ERROR" && "$response" != "TRANSPORT_ERROR" && -n "$response" && ${#response} -gt $min_response_length ]]; then
        echo "✅ PASS: Generated $(echo "$response" | wc -w) words"
        echo "Preview: $(echo "$response" | head -c 80)..."
        ((passed++))
    else
        # Provide detailed diagnostics for different failure types
        if [[ "$response" == "TRANSPORT_ERROR" ]]; then
            echo "❌ FAIL: Transport error (curl exit code: $CURL_EXIT)"
        elif [[ "$response" == "ERROR" ]] || [[ -z "$response" ]]; then
            echo "❌ FAIL: No valid response generated (HTTP $http_code)"
            if [[ -n "${body:-}" ]]; then
              echo "Body (preview): $(echo "$body" | head -c 200)..."
            fi
        else
            echo "❌ FAIL: Response too short (HTTP $http_code)"
            if [[ -n "${body:-}" ]]; then
              echo "Body (preview): $(echo "$body" | head -c 200)..."
            fi
        fi
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
