#!/usr/bin/env bash
set -Eeuo pipefail
if systemctl is-active --quiet ollama; then
  echo "Ollama status: active (running)"
else
  echo "Ollama status: inactive"
fi
