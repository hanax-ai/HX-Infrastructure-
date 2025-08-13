#!/usr/bin/env bash
set -euo pipefail

# Enhanced smoke test with comprehensive validation
HOST="${1:-127.0.0.1}"
PORT="${2:-11434}"
TIMEOUT="${3:-10}"

echo "=== Ollama Comprehensive Smoke Test ==="
echo "Target: http://${HOST}:${PORT}"
echo "Timeout: ${TIMEOUT}s"
echo ""

# Test 1: Root endpoint liveness
echo "[TEST 1] Root endpoint liveness check"
if response=$(timeout "${TIMEOUT}s" curl -s "http://${HOST}:${PORT}/" 2>/dev/null) && echo "$response" | grep -q "Ollama is running"; then
  echo "✅ Root endpoint: Service is running"
else
  echo "❌ Root endpoint: Service not responding" >&2
  exit 1
fi

# Test 2: Version endpoint
echo ""
echo "[TEST 2] Version endpoint validation"
if version_json=$(timeout "${TIMEOUT}s" curl -fsS "http://${HOST}:${PORT}/api/version" 2>/dev/null); then
  version=$(echo "$version_json" | jq -r '.version' 2>/dev/null || echo "unknown")
  echo "✅ Version endpoint: $version"
  echo "   Response: $version_json"
else
  echo "❌ Version endpoint: Failed to retrieve" >&2
  exit 1
fi

# Test 3: Tags endpoint (model registry)
echo ""
echo "[TEST 3] Model registry validation"
if tags_json=$(timeout "${TIMEOUT}s" curl -fsS "http://${HOST}:${PORT}/api/tags" 2>/dev/null); then
  model_count=$(echo "$tags_json" | jq '.models | length' 2>/dev/null || echo "0")
  echo "✅ Model registry: Accessible ($model_count models)"
  echo "   Response: $tags_json"
  
  if [ "$model_count" = "0" ]; then
    echo "   ℹ️  No models installed - /api/generate will not work until models are added"
  fi
else
  echo "❌ Model registry: Failed to retrieve" >&2
  exit 1
fi

echo ""
echo "🎉 All smoke tests passed successfully!"
echo "✅ Service is healthy and ready for use"
