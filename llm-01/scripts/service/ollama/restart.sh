#!/usr/bin/env bash
set -Eeuo pipefail
sudo systemctl restart ollama
sleep 5
systemctl is-active --quiet ollama && echo "Ollama restarted successfully!" || { echo "Ollama failed to restart."; exit 1; }
