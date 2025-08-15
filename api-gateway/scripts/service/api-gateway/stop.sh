#!/usr/bin/env bash
set -euo pipefail
echo "Executing: Stop HX LiteLLM Gateway"
sudo systemctl stop hx-litellm-gateway
sleep 5
if ! sudo systemctl is-active --quiet hx-litellm-gateway; then
  echo "HX LiteLLM Gateway stopped successfully!"
else
  echo "ERROR: HX LiteLLM Gateway failed to stop." >&2; exit 1
fi
