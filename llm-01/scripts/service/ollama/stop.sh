#!/usr/bin/env bash
set -Eeuo pipefail
sudo systemctl stop ollama
sleep 5
systemctl is-active --quiet ollama && { echo "Ollama is still running."; exit 1; } || echo "Ollama stopped successfully!"
