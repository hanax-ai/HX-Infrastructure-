#!/usr/bin/env bash
set -euo pipefail
echo "[SMOKE] DB/Cache/Qdrant + routes"

KEY="sk-hx-dev-1234"
GW="http://127.0.0.1:4000"  # LiteLLM
WR="http://127.0.0.1:4010"  # Wrapper

echo "-> Base models"
curl -fsS -H "Authorization: Bearer $KEY" "$GW/v1/models" >/dev/null

echo "-> Wrapper dep health (must be true/true/true)"
curl -fsS "$WR/healthz/deps" | jq -e '.postgres and .redis and .qdrant' >/dev/null

echo "-> Admin endpoints (DB-backed; status varies by auth policy)"
for EP in "/v1/keys" "/v1/api_keys" "/v1/teams" "/v1/users"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $KEY" "$GW$EP" || true)
  case "$code" in
    200|401|403) echo "$EP reachable ✅ (status $code)";;
    *) echo "WARN: $EP returned $code";;
  esac
done

echo "[SMOKE] done."
