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

# -------- DB/Cache/Vector (from environment or secure files) --------
PG_URL="${PG_URL:-$(cat /etc/hx/db_credentials 2>/dev/null | grep '^PG_URL=' | cut -d= -f2- || echo '')}"
PG_URL_PG="${PG_URL_PG:-$(cat /etc/hx/db_credentials 2>/dev/null | grep '^PG_URL_PG=' | cut -d= -f2- || echo '')}"
REDIS_URL="${REDIS_URL:-$(cat /etc/hx/redis_credentials 2>/dev/null | grep '^REDIS_URL=' | cut -d= -f2- || echo '')}"
QDRANT_URL_HTTP="${QDRANT_URL_HTTP:-http://192.168.10.30:6333}"

# Validate required credentials are available
if [[ -z "$PG_URL" ]]; then
    echo "ERROR: PG_URL not set in environment or /etc/hx/db_credentials" >&2
    exit 1
fi
if [[ -z "$PG_URL_PG" ]]; then
    echo "ERROR: PG_URL_PG not set in environment or /etc/hx/db_credentials" >&2
    exit 1
fi
if [[ -z "$REDIS_URL" ]]; then
    echo "ERROR: REDIS_URL not set in environment or /etc/hx/redis_credentials" >&2
    exit 1
fi

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

# Set environment variables for secure credential handling
export DATABASE_URL="$PG_URL"
export REDIS_URL="$REDIS_URL"

# Patch using ruamel.yaml to avoid sed/indent bugs
python3 - "$CFG_FILE" <<'PY'
import sys
import os
import tempfile
import shutil
import stat
from ruamel.yaml import YAML

cfg_path = sys.argv[1]

# Read credentials from environment variables with validation
database_url = os.getenv('DATABASE_URL')
redis_url = os.getenv('REDIS_URL')

if not database_url:
    print("ERROR: DATABASE_URL environment variable is required", file=sys.stderr)
    sys.exit(1)

if not redis_url:
    print("ERROR: REDIS_URL environment variable is required", file=sys.stderr)
    sys.exit(1)

yaml = YAML()
yaml.preserve_quotes = True

try:
    # Read and validate YAML file
    with open(cfg_path, 'r', encoding='utf-8') as f:
        data = yaml.load(f)
    
    if data is None:
        data = {}
    
    if not isinstance(data, dict):
        print("ERROR: Config file must contain a YAML mapping/dictionary", file=sys.stderr)
        sys.exit(1)
    
    # Validate litellm_settings section
    sec = data.get('litellm_settings')
    if sec is None:
        sec = {}
        data['litellm_settings'] = sec
    
    if not isinstance(sec, dict):
        print("ERROR: litellm_settings must be a dictionary", file=sys.stderr)
        sys.exit(1)
    
    # Apply configuration updates (credentials not logged)
    sec['database_url'] = database_url
    sec['redis_url'] = redis_url
    sec['proxy_logging'] = True
    sec['store_db_logs'] = True
    
    # Write atomically to temporary file then move
    temp_fd, temp_path = tempfile.mkstemp(suffix='.yaml', dir=os.path.dirname(cfg_path))
    try:
        with os.fdopen(temp_fd, 'w', encoding='utf-8') as temp_f:
            yaml.dump(data, temp_f)
        
        # Set secure permissions (readable by owner and group only)
        os.chmod(temp_path, stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP)
        
        # Atomic move
        shutil.move(temp_path, cfg_path)
        print("YAML configuration updated successfully")
        
    except Exception as e:
        # Clean up temp file on error
        try:
            os.unlink(temp_path)
        except:
            pass
        raise e

except FileNotFoundError:
    print(f"ERROR: Config file not found: {cfg_path}", file=sys.stderr)
    sys.exit(1)
except PermissionError as e:
    print(f"ERROR: Permission denied accessing config file: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: Failed to update configuration: {e}", file=sys.stderr)
    sys.exit(1)
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
import sys
import os
try:
    import psycopg
    import redis
    import requests
except ImportError as e:
    print(f"Missing dependency: {e}", file=sys.stderr)
    sys.exit(1)

pg_url = os.getenv('PG_URL_PG', '$PG_URL_PG')
redis_url = os.getenv('REDIS_URL', '$REDIS_URL')
qdrant_url = os.getenv('QDRANT_URL_HTTP', '$QDRANT_URL_HTTP')

try:
    with psycopg.connect(pg_url) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1;")
    print("PG ok")
except Exception as e:
    print(f"PG fail: {e}", file=sys.stderr)
    sys.exit(2)

try:
    r = redis.from_url(redis_url)
    assert r.ping() is True
    print("Redis ok")
except Exception as e:
    print(f"Redis fail: {e}", file=sys.stderr)
    sys.exit(3)

try:
    res = requests.get(f'{qdrant_url}/collections', timeout=5)
    if res.ok:
        print("Qdrant ok")
    else:
        print(f"Qdrant fail: status {res.status_code}", file=sys.stderr)
        sys.exit(4)
except Exception as e:
    print(f"Qdrant fail: {e}", file=sys.stderr)
    sys.exit(4)
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
# Use environment variable for API key, fallback to dev key for testing
KEY="${LITELLM_API_KEY:-sk-hx-dev-1234}"
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
