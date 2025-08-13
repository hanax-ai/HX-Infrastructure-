#!/usr/bin/env bash
set -euo pipefail
echo "Executing: Start Ollama"
sudo systemctl start ollama
sleep 5
if sudo systemctl is-active --quiet ollama; then
  echo "Ollama started successfully!"
else
  echo "ERROR: Ollama failed to start." >&2; exit 1
fi
