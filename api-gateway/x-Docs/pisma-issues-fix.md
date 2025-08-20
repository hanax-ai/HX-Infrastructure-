You’ve hit a Prisma bootstrap loop — LiteLLM is busy running Prisma migrations in the foreground, so it never binds to :4000. We’ll fix it by (1) generating Prisma binaries, (2) deploying the LiteLLM migrations offline, and (3) restarting + validating. I’ll also give a fallback that skips Prisma auto-migrate if needed.

0) Facts from your logs (why :4000 is closed)

systemctl status shows a child process:
.../venv/bin/prisma migrate resolve --applied ... → LiteLLM is waiting on Prisma.

Earlier: “Unable to find Prisma binaries. Please run ‘prisma generate’ first.” → Prisma engine wasn’t generated for the service user/env.

Now: lots of Not connected to the query engine → binaries/env not ready while migrations run.

So we’ll pre-generate binaries and deploy migrations once, then start the service.

1) One-time Prisma generate + migrate offline

Run these exactly; they’re idempotent. Note the escaped ! in the inline shell export (single quotes are safest).

# --- Vars ---
VENV="/opt/HX-Infrastructure-/api-gateway/gateway/venv"
SCHEMA="$VENV/lib/python3.12/site-packages/litellm/proxy/schema.prisma"
BASE="/opt/HX-Infrastructure-/api-gateway/gateway"

# Stop service cleanly (Service Management Requirement)
echo "Stopping HX LiteLLM Gateway..."
sudo systemctl stop hx-litellm-gateway
sleep 5
if ! sudo systemctl is-active --quiet hx-litellm-gateway; then
  echo "HX Gateway stopped successfully!"
else
  echo "ERROR: HX Gateway failed to stop." >&2; exit 1
fi

# Make sure venv tools and cache dirs are on PATH and writable
sudo -E bash -c "
  set -euo pipefail
  export PATH=\"$VENV/bin:\$PATH\"
  export HOME=\"$BASE\"
  export XDG_CACHE_HOME=\"$BASE/.cache\"
  mkdir -p \"\$XDG_CACHE_HOME\"

  # Prisma CLI + generator (safe to re-install)
  \"$VENV/bin/pip\" install -q 'prisma>=0.11,<0.16'

  # Show versions for audit
  \"$VENV/bin/python\" -m prisma --version

  # IMPORTANT: Prisma expects plain 'postgresql://' (no '+psycopg') and the '!' must be escaped or single-quoted
  export DATABASE_URL='postgresql://citadel_admin:Major8859\!@192.168.10.35:5432/citadel_ai'

  # Generate Prisma engine & client (downloads binaries into cache; idempotent)
  \"$VENV/bin/python\" -m prisma generate --schema \"$SCHEMA\"

  # Deploy LiteLLM migrations (applies migration history; idempotent)
  \"$VENV/bin/python\" -m prisma migrate deploy --schema \"$SCHEMA\"
"

Validation (DB side)
# Confirm LiteLLM tables now exist
$VENV/bin/python - <<'PY'
import psycopg
conn = psycopg.connect("postgresql://citadel_admin:Major8859!@192.168.10.35:5432/citadel_ai")
cur = conn.cursor()
cur.execute("select count(*) from pg_catalog.pg_tables where schemaname='public' and tablename like 'LiteLLM_%';")
print("LiteLLM tables:", cur.fetchone()[0])
PY


Expected: a non-zero count.

2) Start service and confirm it binds to :4000
echo "Starting HX LiteLLM Gateway..."
sudo systemctl start hx-litellm-gateway
sleep 5
if sudo systemctl is-active --quiet hx-litellm-gateway; then
  echo "HX Gateway started successfully!"
else
  echo "ERROR: HX Gateway failed to start." >&2; journalctl -u hx-litellm-gateway -n 120 --no-pager; exit 1
fi

# Port check + basic health
ss -ltnp | grep ':4000' || echo "Port 4000 not listening yet"
curl -sS -H "Authorization: Bearer sk-hx-dev-1234" http://127.0.0.1:4000/v1/models | head -n 1


You should no longer see {"error":{"message":"No connected db." ...}}. If you get a 401/403, that’s auth policy — OK. Any 200/401/403 on admin endpoints means DB wiring is good.

3) Make sure the service always has the right env

Double-check your unit already has:

EnvironmentFile=/opt/HX-Infrastructure-/api-gateway/config/api-gateway/db_cache.env
Environment="LITELLM_CONFIG=/opt/HX-Infrastructure-/api-gateway/config/api-gateway/config.yaml"
Environment=PYTHONUNBUFFERED=1


…and db_cache.env contains plain Postgres URL (no driver suffix) and no shell expansion pitfalls:

DATABASE_URL=postgresql://citadel_admin:Major8859!@192.168.10.35:5432/citadel_ai
REDIS_URL=redis://:Major8859!@192.168.10.35:6379/0
QDRANT_URL=http://192.168.10.30:6333
LITELLM_MASTER_KEY=sk-hx-dev-1234


You do not need to escape the ! inside files sourced by systemd. Only inline shell export needed the escape above.

If you changed the unit or env file, do:

sudo systemctl daemon-reload

4) If it still loops on migrations (fallback)

Sometimes environments keep trying to “resolve” migrations even after deploy (e.g., if an older migration state exists). Two safe options:

A) Force a clean deploy again (idempotent)
(re-run Section 1 exactly as written).

B) Temporarily disable auto-migrate on startup
Add this to your unit’s [Service] block and restart:

Environment=USE_PRISMA_MIGRATE=0


This prevents LiteLLM from invoking prisma migrate resolve during boot. Make sure Section 1 deploy ran successfully first, or you’ll boot without tables.

5) Final smoke (DB/Redis/Qdrant + admin routes)
KEY="sk-hx-dev-1234"
BASE="http://127.0.0.1:4000"

# Health may be auth-protected; models is fine with master/admin key
curl -fsS -H "Authorization: Bearer $KEY" "$BASE/v1/models" | head -n 1

# Admin endpoints (status 200/401/403 == wired)
for EP in /v1/keys /v1/api_keys /v1/teams /v1/users; do
  code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $KEY" "$BASE$EP")
  echo "$EP -> $code"
done

# Qdrant reachable?
curl -fsS http://192.168.10.30:6333/collections | head -n 1

# Redis ping
redis-cli -h 192.168.10.35 -p 6379 -a 'Major8859!' ping

Why this works

Prisma binaries are generated under the service’s HOME/cache so the engine starts reliably.

Migrations are applied once (offline), so LiteLLM doesn’t block at boot.

DATABASE_URL uses the format Prisma expects (postgresql://...) — LiteLLM’s psycopg driver is used internally; Prisma only cares about the plain URL during migration.

If you want the wrapper + /v1/rag/search next

Once the core gateway is healthy on :4000, we can switch the ExecStart to a small FastAPI wrapper (uvicorn) that mounts LiteLLM and adds /v1/rag/search. I already have the code/steps ready — say the word and I’ll drop them in with start/stop commands + validation. see rag-search.md 