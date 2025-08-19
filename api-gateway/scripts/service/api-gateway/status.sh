#!/usr/bin/env bash
set -euo pipefail
echo "HX LiteLLM Gateway status:"
sudo systemctl status --no-pager hx-litellm-gateway || true
echo "--- logs (last 20) ---"
sudo journalctl -u hx-litellm-gateway -n 20 --no-pager || true
echo "--- API health (/v1/models) ---"
curl -fsS --max-time 10 http://127.0.0.1:4000/v1/models \
  -H "Authorization: Bearer ${MASTER_KEY}" \
  -H "Content-Type: application/json" >/dev/null \
  && echo "✅ Gateway responding" || { echo "❌ Gateway not responding"; exit 1; }
