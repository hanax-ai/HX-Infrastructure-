#!/usr/bin/env bash
set -euo pipefail

# Error trap for improved diagnostics
trap 'exit_code=$?; echo "ERROR: Script failed at line $LINENO with exit code $exit_code" >&2; echo "Failed command: $BASH_COMMAND" >&2; exit $exit_code' ERR
trap 'exit_code=$?; if [ $exit_code -ne 0 ]; then echo "Script exited with code $exit_code" >&2; fi' EXIT

echo "=== [HX llm-02] Step 2: Installing Ollama Package ==="

if command -v ollama &>/dev/null; then
  echo "Ollama is already installed. Skipping."
else
  echo "Installing Ollama..."
  curl -fsSL https://ollama.ai/install.sh | sh
fi

# Validation
if ! sudo systemctl cat ollama >/dev/null 2>&1; then
  echo "CRITICAL: Ollama systemd unit is missing. Aborting." >&2
  exit 1
fi

# Check Ollama version and capture both stdout and stderr
if version_output=$(ollama --version 2>&1); then
  echo "Ollama version: $version_output"
  echo "Ollama installation validated."
else
  echo "ERROR: Ollama version check failed." >&2
  echo "Command output: $version_output" >&2
  exit 1
fi
