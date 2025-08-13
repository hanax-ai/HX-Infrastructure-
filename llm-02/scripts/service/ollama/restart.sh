#!/usr/bin/env bash
set -euo pipefail
echo "Executing: Restart Ollama"
sudo systemctl restart ollama
sleep 5
if sudo systemctl is-active --quiet ollama; then
  echo "Ollama restarted successfully and is responding"
else
  echo "ERROR: Ollama failed to restart - check logs at /opt/hx-infrastructure/logs/services/ollama" >&2; exit 1
fi
