# Database Integration Specification
# HX Gateway Wrapper - Postgres + Redis Configuration

## Overview
This specification addresses the "No connected db" error from LiteLLM by implementing 
proper Postgres and Redis integration for the HX Gateway system.

## Current Status
- ✅ HX Gateway Wrapper: Fully operational on port 4010
- ✅ Reverse Proxy: Working correctly, forwarding all requests
- ⚠️ LiteLLM Backend: Requires database configuration
- 🔄 Next Step: Implement database integration per this specification

## Implementation Guide

### Step 0: Database Endpoints Configuration
```bash
# <<< EDIT THESE VALUES FOR YOUR ENVIRONMENT >>>
export PG_HOST="192.168.10.X"         # Postgres server
export PG_PORT="5432"
export PG_DB="hx_gateway"
export PG_USER="hx_gateway"
export PG_PASS="REDACTED"

export REDIS_HOST="192.168.10.Y"      # Redis server
export REDIS_PORT="6379"
export REDIS_PASS="REDACTED"
```

### Step 1: Create Sealed Environment File for SystemD

**Important**: If your PG_USER or PG_PASS contain special characters (@ : / % etc.), you must percent-encode them before using in DATABASE_URL. For example, a password like "pass@word" should become "pass%40word". Use a URL encoder tool or shell command like `python3 -c "import urllib.parse; print(urllib.parse.quote('your_password'))"` to generate safe values.

```bash
export BASE="/opt/HX-Infrastructure-/api-gateway"
sudo install -d -m 0755 "$BASE/config/api-gateway"

sudo bash -c "cat > $BASE/config/api-gateway/gateway.env" <<EOF
# Postgres (LiteLLM will auto-initialize tables on start)
DATABASE_URL=postgresql://${PG_USER}:${PG_PASS}@${PG_HOST}:${PG_PORT}/${PG_DB}

# Redis (for cache/rate-limit if enabled)
REDIS_URL=redis://:${REDIS_PASS}@${REDIS_HOST}:${REDIS_PORT}/0

# Optional hardening / switches
DISABLE_ADMIN_UI=true
EOF

# Lock it down for the service user
sudo chown root:hx-gateway "$BASE/config/api-gateway/gateway.env"
sudo chmod 640 "$BASE/config/api-gateway/gateway.env"
```

### Step 2: Point Both Units at the Environment File
```bash
# Core LiteLLM proxy (port 4000)
sudo mkdir -p /etc/systemd/system/hx-litellm-gateway.service.d
sudo bash -c 'cat > /etc/systemd/system/hx-litellm-gateway.service.d/30-db.conf' <<'EOF'
[Service]
EnvironmentFile=/opt/HX-Infrastructure-/api-gateway/config/api-gateway/gateway.env
EOF

# SOLID wrapper (port 4010)
sudo mkdir -p /etc/systemd/system/hx-gateway-ml.service.d
sudo bash -c 'cat > /etc/systemd/system/hx-gateway-ml.service.d/30-db.conf' <<'EOF'
[Service]
EnvironmentFile=/opt/HX-Infrastructure-/api-gateway/config/api-gateway/gateway.env
EOF

sudo systemctl daemon-reload
```

### Step 3: Re-enable DB Features in config.yaml
```bash
export CFG="$BASE/config/api-gateway/config.yaml"

# Remove db-less flags if present
sudo sed -i '/^[[:space:]]*disable_spend_logs:/d' "$CFG"
sudo sed -i '/^[[:space:]]*disable_error_logs:/d' "$CFG"

# Ensure general_settings exists, then add positive flags
grep -q '^general_settings:' "$CFG" || \
  sudo sed -i '1igeneral_settings:' "$CFG"

sudo awk 'BEGIN{done=0}
  /^general_settings:/ && !done {print; print "  disable_spend_logs: false"; print "  disable_error_logs: false"; done=1; next}
  {print}' "$CFG" | sudo tee "$CFG.tmp" >/dev/null && sudo mv "$CFG.tmp" "$CFG"
```

**Note**: Admin UI stays off via `DISABLE_ADMIN_UI=true` (safer); switch to false later if you want the console.

### Step 4: (Optional) Enable Redis Cache/Rate-Limits

**Option A (Recommended)**: Add LITELLM_REDIS_URL to the shared gateway.env file and use EnvironmentFile:
```bash
# Add Redis URL to shared environment file
sudo bash -c "echo 'LITELLM_REDIS_URL=\${REDIS_URL}' >> $BASE/config/api-gateway/gateway.env"

# Create cache configuration without duplicating environment variables
sudo bash -c 'cat > /etc/systemd/system/hx-litellm-gateway.service.d/40-cache.conf' <<'EOF'
[Service]
# LiteLLM cache (Redis) - REDIS_URL comes from gateway.env
Environment=LITELLM_CACHE=1
# Example simple rate limit: 60 req/min per key (adjust later in config if needed)
Environment=LITELLM_RATE_LIMIT_ENABLED=1
Environment=LITELLM_RATE_LIMIT_TOKENS_PER_MINUTE=60
EOF

sudo systemctl daemon-reload
```

*Note: You can mirror the same drop-in for hx-gateway-ml if your wrapper reads the same flags.*

### Step 5: Restart Services (HX Pattern)
```bash
sudo systemctl restart hx-litellm-gateway
sleep 5 && sudo systemctl is-active --quiet hx-litellm-gateway || { echo "liteLLM failed"; exit 1; }

sudo systemctl restart hx-gateway-ml
sleep 5 && sudo systemctl is-active --quiet hx-gateway-ml || { echo "wrapper failed"; exit 1; }
```

### Step 6: Validation (No More "No connected db.")
```bash
# Wrapper health
curl -s http://127.0.0.1:4010/healthz | jq .

# Models (should list all; no DB error)
curl -s http://127.0.0.1:4010/v1/models -H "Authorization: Bearer sk-hx-dev-1234" | jq .

# Embedding via wrapper
curl -s http://127.0.0.1:4010/v1/embeddings \
 -H "Authorization: Bearer sk-hx-dev-1234" -H "Content-Type: application/json" \
 -d '{"model":"emb-premium","input":"HX-OK"}' | jq '.data[0].embedding | length'

# Deterministic chat
curl -s http://127.0.0.1:4010/v1/chat/completions \
 -H "Authorization: Bearer sk-hx-dev-1234" -H "Content-Type: application/json" \
 -d '{"model":"hx-chat","messages":[{"role":"user","content":"Return exactly the text: HX-OK"}],"max_tokens":10,"temperature":0}' \
 | jq -r '.choices[0].message.content'
```

### Troubleshooting
If anything's off:
```bash
sudo journalctl -u hx-litellm-gateway -n 80 --no-pager
sudo journalctl -u hx-gateway-ml -n 80 --no-pager
```

## Database Setup Requirements

### Postgres (on DB host)
```sql
-- Run as postgres superuser (psql)
CREATE DATABASE hx_gateway;
CREATE USER hx_gateway WITH PASSWORD 'REDACTED';
GRANT ALL PRIVILEGES ON DATABASE hx_gateway TO hx_gateway;
```

*Optionally enforce TLS/pg_hba rules as you move toward prod.*

### Redis (on Redis host)
If ACLs are enabled:
```redis
ACL SETUSER hxgateway on >REDACTED ~* +@all
```

…and adjust `REDIS_URL` to `redis://:REDACTED@HOST:6379/0`.

## Rollback to DB-less (Kept Simple)

If you ever need to drop DB again:
```bash
# Set base paths
BASE="/opt/HX-Infrastructure-/api-gateway"
CFG="${BASE}/config/api-gateway/config.yaml"

# Validate BASE directory exists
if [[ -z "$BASE" ]]; then
    echo "ERROR: BASE variable is not set" >&2
    exit 1
fi

if [[ ! -d "$BASE" ]]; then
    echo "ERROR: BASE directory does not exist: $BASE" >&2
    exit 1
fi

# Validate CFG file exists
if [[ -z "$CFG" ]]; then
    echo "ERROR: CFG variable is not set" >&2
    exit 1
fi

if [[ ! -f "$CFG" ]]; then
    echo "ERROR: Config file not found: $CFG" >&2
    exit 1
fi

sudo rm -f /etc/systemd/system/hx-*-service.d/30-db.conf /etc/systemd/system/hx-*-service.d/40-cache.conf
sudo sed -i '/^[[:space:]]*disable_spend_logs:/d' "$CFG"; sudo sed -i '/^[[:space:]]*disable_error_logs:/d' "$CFG"
sudo awk 'BEGIN{done=0}
  /^general_settings:/ && !done {print; print "  disable_spend_logs: true"; print "  disable_error_logs: true"; done=1; next}
  {print}' "$CFG" | sudo tee "$CFG.tmp" >/dev/null && sudo mv "$CFG.tmp" "$CFG"
sudo systemctl daemon-reload
sudo systemctl restart hx-litellm-gateway hx-gateway-ml
```

## Why This Setup

1. **Resolves Database Error**: Stops the "No connected db." by giving LiteLLM a valid `DATABASE_URL`
2. **Security Hardening**: Keeps admin surface dark (`DISABLE_ADMIN_UI=true`) for now
3. **Performance**: Lets you layer Redis for cache/rate-limits without touching code
4. **Security**: Secrets isolated in a 640 env file, loaded by systemd drop-ins (HX style)
5. **Maintainability**: Clean separation of concerns, easy rollback capability

## Expected Results After Implementation

- ✅ `/v1/models` returns JSON model list instead of database error
- ✅ `/v1/chat/completions` processes requests successfully  
- ✅ `/v1/embeddings` with input→prompt transformation working
- ✅ Request logging and analytics in Postgres
- ✅ Optional performance caching via Redis
- ✅ Optional rate limiting capabilities
- ✅ Full SOLID pipeline operational end-to-end

---

**Implementation Priority**: Medium  
**Estimated Effort**: 2-4 hours  
**Dependencies**: Database server access and credentials  
**Status**: Ready for implementation
