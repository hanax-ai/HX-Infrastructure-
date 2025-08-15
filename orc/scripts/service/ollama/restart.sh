#!/usr/bin/env bash
echo "Executing: Restart Ollama"
sudo systemctl restart ollama
sleep 5
if sudo systemctl is-active --quiet ollama; then
    echo "✅ Ollama restarted successfully!"
else
    echo "❌ ERROR: Ollama failed to restart." >&2
    exit 1
fi
