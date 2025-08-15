#!/usr/bin/env bash
set -e
echo "--- Running Comprehensive Smoke Test ---"
echo -n "1. Checking API root... "
curl -fsS http://127.0.0.1:11434/ > /dev/null
echo "OK"

echo -n "2. Validating API version... "
curl -fsS http://127.0.0.1:11434/api/version | jq -e '.version' > /dev/null
echo "OK"

echo -n "3. Checking model tags... "
curl -fsS http://127.0.0.1:11434/api/tags | jq -e '.models' > /dev/null
echo "OK"

echo "✅ Comprehensive smoke test passed."
