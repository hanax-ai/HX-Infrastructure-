#!/usr/bin/env bash
set -euo pipefail

# Dependencies preflight
for bin in curl jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "❌ Missing dependency: $bin"
    exit 127
  fi
done

# SOLID: Single Responsibility - Test ONLY mistral availability
# Configuration - Environment variables with fallbacks (SOLID: Dependency Inversion)
API_BASE="${API_BASE:-http://localhost:4000}"

# Validate required authentication
if [[ -z "${MASTER_KEY:-}" ]]; then
    echo "ERROR: MASTER_KEY environment variable is required" >&2
    exit 1
fi

MODEL_NAME="${MODEL_NAME:-llm01-mistral-small3.2}"

echo "🔍 Testing Mistral Model Availability"
echo "====================================="
echo "Model: $MODEL_NAME"
echo "Gateway: $API_BASE"
echo

# Test model availability in gateway
echo "Checking model availability..."
if resp="$(curl -fsS --max-time 30 -H "Authorization: Bearer ${MASTER_KEY}" "${API_BASE}/v1/models")"; then
  if jq -e --arg id "$MODEL_NAME" '.data[] | select(.id==$id)' >/dev/null <<<"$resp"; then
    echo "✅ SUCCESS: Model '$MODEL_NAME' is available in gateway"
    exit 0
  else
    echo "❌ FAIL: Model '$MODEL_NAME' not available in gateway"
    exit 1
  fi
else
  echo "❌ FAIL: Request to ${API_BASE}/v1/models failed"
  exit 2
fi
