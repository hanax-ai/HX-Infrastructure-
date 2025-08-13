#!/usr/bin/env bash
set -euo pipefail
HOST="${1:-127.0.0.1}"
PORT="${2:-11434}"

echo "[SMOKE] GET /api/version on ${HOST}:${PORT}"
curl -fsS "http://${HOST}:${PORT}/api/version" | jq .

echo "[SMOKE] GET /api/tags on ${HOST}:${PORT}"
curl -fsS "http://${HOST}:${PORT}/api/tags" | jq .

echo "[SMOKE] Note: If no models are installed, /api/tags will be empty. Install a test model before /api/generate."
