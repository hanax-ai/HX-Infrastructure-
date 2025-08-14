#!/usr/bin/env bash
echo "Executing: Stop Ollama"
sudo systemctl stop ollama
sleep 5
if ! sudo systemctl is-active --quiet ollama; then
    echo "✅ Ollama stopped successfully!"
else
    echo "❌ ERROR: Ollama failed to stop." >&2
    exit 1
fi
