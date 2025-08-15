#!/usr/bin/env bash
set -e
echo "--- Running Basic Smoke Test ---"
echo -n "Checking API version... "
curl -fsS http://127.0.0.1:11434/api/version | jq .
echo "✅ Basic smoke test passed."
