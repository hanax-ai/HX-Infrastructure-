#!/usr/bin/env bash
echo "--- Ollama Service Status ---"
sudo systemctl status ollama --no-pager
echo
echo "--- API Connectivity Check ---"
if curl -fsS http://127.0.0.1:11434/api/version > /dev/null; then
    echo "✅ API is responding."
else
    echo "❌ API is NOT responding."
fi
