#!/usr/bin/env bash
set -Eeuo pipefail
sudo systemctl start ollama
sleep 5
systemctl is-active --quiet ollama && echo "Ollama started successfully!" || { echo "Ollama failed to start."; exit 1; }
