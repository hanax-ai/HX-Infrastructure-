#!/usr/bin/env bash
set -euo pipefail
echo "Executing: Ollama Status Check"
echo "=== Service Status ==="
sudo systemctl status ollama --no-pager --lines=5
echo -e "\n=== API Health Check ==="
# Primary liveness check against root endpoint
if response=$(timeout 10s curl -s http://localhost:11434/ 2>/dev/null) && echo "$response" | grep -q "Ollama is running"; then
  echo "✅ Ollama started successfully and is responding"
else
  echo "❌ Ollama failed to start - check logs at /opt/hx-infrastructure/logs/services/ollama" >&2; exit 1
fi

# Optional model registry check (set OLLAMA_CHECK_MODELS=true to enable)
if [ "${OLLAMA_CHECK_MODELS:-false}" = "true" ]; then
  echo -e "\n=== Model Registry Check ==="
  if timeout 10s curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo "✅ Model registry accessible"
  else
    echo "⚠️  Model registry check failed (non-critical)" >&2
  fi
fi
