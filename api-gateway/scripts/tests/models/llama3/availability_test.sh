#!/usr/bin/env bash
set -euo pipefail

# Dependencies preflight
for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Missing dependency: $cmd"
        exit 2
    fi
done

# SOLID: Single Responsibility - Test ONLY llama3 availability
# Configuration - Environment variables with fallbacks (SOLID: Dependency Inversion)
API_BASE="${API_BASE:-http://localhost:4000}"

# Require explicit authentication token
if [[ -z "${MASTER_KEY:-}" ]]; then
    echo "❌ MASTER_KEY environment variable must be set"
    echo "   Please provide authentication credentials"
    exit 1
fi

MODEL_NAME="llm01-llama3.2-3b"

echo "🔍 Testing Llama3 Model Availability"
echo "===================================="
echo "Model: $MODEL_NAME"
echo "Gateway: $API_BASE"
echo

# Test model availability in gateway
echo "Checking model availability..."
if curl -fS -H "Authorization: Bearer ${MASTER_KEY}" "${API_BASE}/v1/models" \
    | jq -e --arg id "$MODEL_NAME" '.data[] | select(.id == $id)' >/dev/null 2>&1; then
    echo "✅ SUCCESS: Model '$MODEL_NAME' is available in gateway"
    exit 0
else
    echo "❌ FAIL: Model '$MODEL_NAME' not available in gateway"
    exit 1
fi
