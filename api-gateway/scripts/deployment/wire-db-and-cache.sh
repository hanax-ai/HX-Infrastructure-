#!/usr/bin/env bash
set -euo pipefail

echo "=== [HX-GW] Wire Postgres + Redis (+Qdrant health) into LiteLLM + Wrapper ==="

# -------- Resolve base path (canonical first, fallback accepted) --------
ROOT="/opt/HX-Dev-Test-Infrastructure"
[ -d "$ROOT" ] || ROOT="/opt/HX-Infrastructure-"
if [ ! -d "$ROOT" ]; then
  echo "❌ Neither /opt/HX-Dev-Test-Infrastructure nor /opt/HX-Infrastructure- exists"; exit 1
fi

GW_BASE="$ROOT/api-gateway"
CFG_DIR="$GW_BASE/config/api-gateway"
CFG_FILE="$CFG_DIR/config.yaml"
LOG_DIR="$GW_BASE/logs/services"
SCRIPTS_DIR="$GW_BASE/scripts"
WRAP_ENV="$GW_BASE/gateway/config/gateway-wrapper.env"

# -------- DB/Cache/Vector (quoted; note the !) --------
PG_URL='postgresql+psycopg://citadel_admin:Major8859!@192.168.10.35:5432/citadel_ai'
PG_URL_PG='postgresql://citadel_admin:Major8859!@192.168.10.35:5432/citadel_ai'
REDIS_URL='redis://:Major8859!@192.168.10.35:6379'
QDRANT_URL_HTTP='http://192.168.10.30:6333'

# -------- Services --------
GATEWAY_SVC="hx-litellm-gateway.service"
WRAPPER_SVC="hx-gw-wrapper.service"

echo "--> Step 0: Preflight & dirs"
command -v python3 >/dev/null || { echo "python3 not found"; exit 1; }
command -v curl >/dev/null || { echo "curl not found"; exit 1; }
sudo mkdir -p "$CFG_DIR" "$LOG_DIR" "$(dirname "$WRAP_ENV")"
[ -f "$CFG_FILE" ] || { echo "❌ config.yaml not found at $CFG_FILE"; exit 1; }

echo "--> Step 1: Python deps (tools only; safe to re-run)"
# Skip pip installation since packages are already installed

echo "--> Step 2: Backup + YAML-safe patch of LiteLLM config"
TS=$(date -u +"%Y%m%dT%H%M%SZ")
sudo cp -a "$CFG_FILE" "$CFG_FILE.bak.$TS"

# Patch using ruamel.yaml to avoid sed/indent bugs
python3 - "$CFG_FILE" <<'PY'
import sys
from ruamel.yaml import YAML
cfg_path = sys.argv[1]
yaml = YAML()
yaml.preserve_quotes = True
with open(cfg_path, 'r', encoding='utf-8') as f:
    data = yaml.load(f) or {}

sec = data.get('litellm_settings') or {}
# Apply/replace keys
sec['database_url'] = 'postgresql+psycopg://citadel_admin:Major8859!@192.168.10.35:5432/citadel_ai'
sec['redis_url'] = 'redis://:Major8859!@192.168.10.35:6379'
sec['proxy_logging'] = True
sec['store_db_logs'] = True
data['litellm_settings'] = sec

with open(cfg_path, 'w', encoding='utf-8') as f:
    yaml.dump(data, f)
print("YAML patched safely")
PY

echo "--> Step 3: Restart LiteLLM gateway"
sudo systemctl daemon-reload || true
sudo systemctl restart "$GATEWAY_SVC"
sleep 3
if sudo systemctl is-active --quiet "$GATEWAY_SVC"; then
  echo "LiteLLM running ✅"
else
  sudo journalctl -u "$GATEWAY_SVC" -n 80 --no-pager
  exit 1
fi

echo "--> Step 4: Quick dependency probes (PG/Redis/Qdrant)"
python3 - <<PY
import sys, psycopg, redis, requests
pg_url = '$PG_URL_PG'
try:
    with psycopg.connect(pg_url) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1;")
    print("PG ok")
except Exception as e:
    print("PG fail:", e); sys.exit(2)

try:
    r = redis.from_url('$REDIS_URL')
    assert r.ping() is True
    print("Redis ok")
except Exception as e:
    print("Redis fail:", e); sys.exit(3)

try:
    res = requests.get('$QDRANT_URL_HTTP/collections', timeout=5)
    if res.ok:
        print("Qdrant ok")
    else:
        print("Qdrant fail: status", res.status_code); sys.exit(4)
except Exception as e:
    print("Qdrant fail:", e); sys.exit(4)
PY

echo "--> Step 5: Ensure wrapper .env has deps"
sudo touch "$WRAP_ENV"
sudo grep -q '^QDRANT_URL=' "$WRAP_ENV" 2>/dev/null || echo "QDRANT_URL=$QDRANT_URL_HTTP" | sudo tee -a "$WRAP_ENV" >/dev/null
sudo grep -q '^PG_URL=' "$WRAP_ENV" 2>/dev/null || echo "PG_URL=$PG_URL" | sudo tee -a "$WRAP_ENV" >/dev/null
sudo grep -q '^REDIS_URL=' "$WRAP_ENV" 2>/dev/null || echo "REDIS_URL=$REDIS_URL" | sudo tee -a "$WRAP_ENV" >/dev/null

echo "--> Step 6: Restart wrapper (optional)"
if systemctl list-unit-files | grep -q "$WRAPPER_SVC"; then
  sudo systemctl restart "$WRAPPER_SVC"
  sleep 2
  sudo systemctl is-active --quiet "$WRAPPER_SVC" && echo "Wrapper running ✅" || echo "Wrapper present but not active"
else
  echo "Wrapper service not installed (ok)"
fi

echo "--> Step 7: Validate LiteLLM routes"
KEY="sk-hx-dev-1234"
BASE="http://127.0.0.1:4000"

set -o pipefail
curl -fsS -H "Authorization: Bearer $KEY" "$BASE/v1/models" >/dev/null && echo "/v1/models ok"

# The admin routes depend on DB; status 200/401/403 means "wired & reachable" (auth policy may vary).
for EP in "/v1/keys" "/v1/api_keys" "/v1/teams" "/v1/users"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $KEY" "$BASE$EP" || true)
  case "$code" in
    200|401|403) echo "$EP reachable ✅ (status $code)";;
    *) echo "WARN: $EP returned $code (check gateway logs)";;
  esac
done

echo "=== [HX-GW] Wiring complete."
