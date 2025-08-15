#!/usr/bin/env bash
set -euo pipefail
echo "Executing: Start HX LiteLLM Gateway"
sudo systemctl enable hx-litellm-gateway >/dev/null 2>&1 || true
sudo systemctl start hx-litellm-gateway
sleep 5
if sudo systemctl is-active --quiet hx-litellm-gateway; then
  echo "HX LiteLLM Gateway started successfully!"
else
  echo "ERROR: HX LiteLLM Gateway failed to start." >&2; exit 1
fi
