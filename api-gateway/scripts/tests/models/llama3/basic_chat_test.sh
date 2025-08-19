#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - Test ONLY llama3 basic chat completion
# Configuration - Environment variables with fallbacks (SOLID: Dependency Inversion)
API_BASE="${API_BASE:-http://localhost:4000}"

# Require explicit authentication token
if [[ -z "${MASTER_KEY:-}" ]]; then
    echo "❌ MASTER_KEY environment variable must be set"
    echo "   Please provide authentication credentials"
    exit 1
fi

MODEL_NAME="llm01-llama3.2-3b"
TEST_PROMPT="Say: TEST-OK"

echo "💬 Testing Llama3 Basic Chat Completion"
echo "======================================="
echo "Model: $MODEL_NAME"
echo "Prompt: $TEST_PROMPT"
echo

# Test basic chat completion
echo "Testing chat completion..."
response=$(
  jq -n \
    --arg model "$MODEL_NAME" \
    --arg prompt "$TEST_PROMPT" \
    --argjson temperature 0.1 \
    --argjson max_tokens 50 \
    '{model:$model, messages:[{role:"user", content:$prompt}], temperature:$temperature, max_tokens:$max_tokens}' \
  | curl -sSf --max-time 30 \
      -H "Authorization: Bearer ${MASTER_KEY}" \
      -H "Content-Type: application/json" \
      -d @- "${API_BASE}/v1/chat/completions" \
  | jq -r '.choices[0].message.content // "ERROR"' 2>/dev/null
)

if [[ "$response" != "ERROR" && -n "$response" ]]; then
    echo "✅ SUCCESS: Chat completion working"
    echo "Response: $(echo "$response" | head -c 100)..."
    exit 0
else
    echo "❌ FAIL: Chat completion failed"
    exit 1
fi
