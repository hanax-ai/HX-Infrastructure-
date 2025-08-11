#!/usr/bin/env bash
set -euo pipefail
PORT="${OLLAMA_PORT:-11434}"
code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${PORT}/api/tags" || true)
if [[ "$code" == "200" ]]; then
  echo "Smoke: /api/tags OK"
  exit 0
else
  echo "Smoke: /api/tags HTTP $code"
  exit 1
fi
