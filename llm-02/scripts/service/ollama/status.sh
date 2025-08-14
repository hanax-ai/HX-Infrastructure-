#!/usr/bin/env bash
set -euo pipefail

# Configuration variables
BASE_URL="http://${OLLAMA_HOST:-localhost}:${OLLAMA_PORT:-11434}"
LOG_DIR="${OLLAMA_LOG_DIR:-/opt/hx-infrastructure/logs/services/ollama}"

echo "Executing: Ollama Status Check"
echo "=== Service Status ==="
sudo systemctl status ollama --no-pager --lines=5
echo -e "\n=== API Health Check ==="
# Primary liveness check against root endpoint
if response=$(curl -sf -m 10 "${BASE_URL}/" 2>/dev/null) && echo "$response" | grep -Fq "Ollama is running"; then
  echo "✅ Ollama started successfully and is responding"
else
  echo "❌ Ollama failed to start - check logs at ${LOG_DIR}" >&2; exit 1
fi

# Optional model registry check (set OLLAMA_CHECK_MODELS=true to enable)
if [ "${OLLAMA_CHECK_MODELS:-false}" = "true" ]; then
  echo -e "\n=== Model Registry Check ==="
  if curl -fsS -m 10 "${BASE_URL}/api/tags" >/dev/null 2>&1; then
    echo "✅ Model registry accessible"
  else
    echo "⚠️  Model registry check failed (non-critical)" >&2
  fi
fi
