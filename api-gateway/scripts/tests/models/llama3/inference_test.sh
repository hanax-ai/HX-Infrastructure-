#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - Test ONLY llama3 inference capability
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
    
    # Execute request with error handling
    if ! response=$(curl -fsS --max-time 45 "${API_BASE}/v1/chat/completions" \
        -H "Authorization: Bearer ${AUTH_KEY}" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        --data-binary "$payload" \
      | jq -r '.choices[0].message.content // "ERROR"'); then
        echo "❌ FAIL: HTTP or parse error"
        continue
    fi

    # Enhanced response validation
    if [[ "$response" == "ERROR" ]]; then
        echo "❌ FAIL: HTTP or parse error"
        continue
    fi
    
    # Trim whitespace from response
    response="$(echo "$response" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    
    # Check if response is empty after trimming
    if [[ -z "$response" ]]; then
        echo "❌ FAIL: Empty response after trimming whitespace"
        continue
    fi
    
    # Check for empty/only punctuation (only punctuation and whitespace)
    if [[ "$response" =~ ^[[:punct:][:space:]]*$ ]]; then
        echo "❌ FAIL: Response contains only punctuation/whitespace"
        continue
    fi
    
    # Check for empty JSON patterns
    if [[ "$response" =~ ^(\{\}|\[\]|null|""|''|\{\s*\}|\[\s*\])$ ]]; then
        echo "❌ FAIL: Response is empty JSON structure"
        continue
    fi
    
    # Check if response starts with JSON markers (raw JSON leak)
    if [[ "$response" =~ ^[\{\[] ]]; then
        echo "❌ FAIL: Response appears to be raw JSON"
        continue
    fi
    
    # Check for common AI-proxy phrases (blacklist)
    if [[ "$response" =~ (I am an AI|I\'m an AI|I\'m an artificial|I am an artificial|I\'m a language model|I am a language model|I\'m just an AI|I am just an AI|I\'m Claude|I am Claude|I\'m ChatGPT|I am ChatGPT|I\'m GPT|I am GPT) ]]; then
        echo "❌ FAIL: Response contains AI self-identification phrases"
        continue
    fi
    
    # Check for very short repeated tokens
    if [[ "$response" =~ ^(.{1,3})\1{3,}$ ]]; then
        echo "❌ FAIL: Response contains excessive repetition of short tokens"
        continue
    fi
    
    # Check minimum length requirement (existing check)
    if [[ ${#response} -le 20 ]]; then
        echo "❌ FAIL: Response too short (${#response} chars, need >20)"
        continue
    fi
    
    # Check minimum word count
    word_count=$(echo "$response" | wc -w)
    if [[ $word_count -lt 5 ]]; then
        echo "❌ FAIL: Response too few words ($word_count words, need ≥5)"
        continue
    fi
    
    # All validation checks passed
    echo "✅ PASS: Generated $word_count words"
    echo "Preview: $(echo "$response" | head -c 100)..."
    ((passed++))
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
