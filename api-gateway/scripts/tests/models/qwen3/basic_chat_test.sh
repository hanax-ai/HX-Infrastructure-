#!/usr/bin/env bash
set -euo pipefail

# Dependencies preflight
for bin in curl jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "❌ Missing dependency: $bin"
    exit 127
  fi
done

# SOLID: Single Responsibility - Test ONLY qwen3 basic chat completion
# Configuration - Environment variables with fallbacks (SOLID: Dependency Inversion)
API_BASE="${API_BASE:-http://localhost:4000}"
# Security: MASTER_KEY must be set externally
if [[ -z "${MASTER_KEY:-}" ]]; then
    echo "❌ ERROR: MASTER_KEY environment variable is required" >&2
    echo "   Please export MASTER_KEY=your-secure-key before running this script" >&2
    exit 1
fi

MODEL_NAME="${MODEL_NAME:-llm01-qwen3-1.7b}"
TEST_PROMPT="What is 2+2?"

echo "💬 Testing Qwen3 Basic Chat Completion"
echo "======================================"
echo "Model: $MODEL_NAME"
echo "Prompt: $TEST_PROMPT"
echo

# Test basic chat completion
echo "Testing chat completion..."
response=$(jq -n \
    --arg model "$MODEL_NAME" \
    --arg prompt "$TEST_PROMPT" \
    --argjson temperature 0 \
    --argjson max_tokens 50 \
    '{
        "model": $model,
        "messages": [{"role": "user", "content": $prompt}],
        "temperature": $temperature,
        "max_tokens": $max_tokens
    }' | curl -fS --max-time 30 "${API_BASE}/v1/chat/completions" \
    -H "Authorization: Bearer ${MASTER_KEY}" \
    -H "Content-Type: application/json" \
    --data-binary @- | jq -r '.choices[0].message.content // "ERROR"' 2>/dev/null)

if [[ "$response" != "ERROR" && -n "$response" && "$response" == *"4"* ]]; then
    echo "✅ SUCCESS: Chat completion working and contains expected answer"
    echo "Response: $(echo "$response" | head -c 100)..."
    exit 0
else
    echo "❌ FAIL: Chat completion failed or does not contain '4'"
    echo "Response: $response"
    exit 1
fi
