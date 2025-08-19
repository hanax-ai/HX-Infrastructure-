#!/usr/bin/env bash
set -euo pipefail

# Validate required dependencies
for cmd in jq curl systemctl find sort head awk xargs tail; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "missing dependency: $cmd is required" >&2
        exit 1
    fi
done

BASE="/opt/HX-Infrastructure-/api-gateway"
LOGDIR="${BASE}/logs/services/gateway"

# Configure API endpoint and authentication
API="${API_URL:-${API:-}}"
if [[ -z "$API" ]]; then
    API="http://127.0.0.1:4000"
    if [[ "${ENV:-${NODE_ENV:-}}" != "development" && -n "${ENV:-${NODE_ENV:-}}" ]]; then
        echo "WARNING: using unsafe default API endpoint in non-development environment" >&2
    fi
fi

AUTH="${MASTER_KEY:-}"
if [[ -z "$AUTH" ]]; then
    AUTH="sk-hx-dev-1234"
    if [[ "${ENV:-${NODE_ENV:-}}" != "development" && -n "${ENV:-${NODE_ENV:-}}" ]]; then
        echo "WARNING: using unsafe default API key in non-development environment" >&2
    fi
fi

echo "=== [validate_restore] Quick probes ==="
echo "--> systemd status"
systemctl is-active --quiet hx-litellm-gateway.service && echo "✅ gateway active" || { echo "❌ gateway inactive"; exit 1; }
curl -fsS --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 2 --retry-connrefused -H "Authorization: Bearer ${AUTH}" -H "Content-Type: application/json" "${API}/v1/models" | jq -e '.data | length > 0' >/dev/null && echo "✅ /v1/models responds"
curl -fsS --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 2 --retry-connrefused -H "Authorization: Bearer ${AUTH}" -H "Content-Type: application/json" \
  -d '{"model":"emb-premium","input":"sanity"}' "${API}/v1/embeddings" | jq -e '.data[0].embedding | length==1024' >/dev/null && echo "✅ /v1/embeddings responds"
curl -fsS --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 2 --retry-connrefused -H "Authorization: Bearer ${AUTH}" -H "Content-Type: application/json" \
  -d '{"model":"hx-chat","messages":[{"role":"user","content":"Return exactly the text: HX-OK"}],"max_tokens":10,"temperature":0}' \
  "${API}/v1/chat/completions" | jq -e '.choices[0].message.content | contains("HX-OK")' >/dev/null && echo "✅ /v1/chat/completions deterministic OK"

echo "--> last smoke log"
find "${LOGDIR}" -type f -name "gw-smoke-*.log" -printf "%T@ %p\n" | sort -nr | head -1 | awk '{print $2}' | xargs -r tail -n +1 || true
echo "✅ Validation complete."
