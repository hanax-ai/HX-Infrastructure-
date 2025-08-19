#!/usr/bin/env bash
set -euo pipefail

# Validate required dependencies
missing_deps=()
for cmd in tar find sha256sum curl python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing_deps+=("$cmd")
    fi
done

# Check for python3 -m pip availability
if ! python3 -m pip --version >/dev/null 2>&1; then
    missing_deps+=("python3-pip")
fi

if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo "missing dependencies: ${missing_deps[*]} are required" >&2
    exit 1
fi

BASE="/opt/HX-Infrastructure-/api-gateway"
BKDIR="${BASE}/gateway/backups"
LOGDIR="${BASE}/logs/services/gateway"
TESTDIR="${BASE}/scripts/tests/gateway"
SRVDIR="${BASE}/scripts/service/api-gateway"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${BKDIR}/gw-checkpoint-${TS}.tgz"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# API and authentication configuration (consistent with validate_restore.sh)
API_URL="${API_URL:-${API:-http://127.0.0.1:4000}}"
# Security: MASTER_KEY must be set externally
if [[ -z "${MASTER_KEY:-}" ]]; then
    echo "❌ ERROR: MASTER_KEY environment variable is required" >&2
    echo "   Please export MASTER_KEY=your-secure-key before running this script" >&2
    exit 1
fi

echo "=== [make_checkpoint] Creating checkpoint @ ${TS} ==="
# Verify expected paths (idempotent + helpful errors)
for P in \
  "${BASE}/config/api-gateway" \
  "/etc/systemd/system/hx-litellm-gateway.service" \
  "/etc/systemd/system/hx-gateway-smoke.service" \
  "/etc/systemd/system/hx-gateway-smoke.timer" \
  "${TESTDIR}" "${SRVDIR}"
do
  [ -e "${P}" ] || { echo "❌ Missing required path: ${P}" >&2; exit 1; }
done

mkdir -p "${TMP}/snapshot"
# 1) Configs
cp -a "${BASE}/config/api-gateway" "${TMP}/snapshot/config"
# 2) Systemd units
mkdir -p "${TMP}/snapshot/systemd"
cp -a /etc/systemd/system/hx-litellm-gateway.service "${TMP}/snapshot/systemd/"
cp -a /etc/systemd/system/hx-gateway-smoke.service   "${TMP}/snapshot/systemd/"
cp -a /etc/systemd/system/hx-gateway-smoke.timer     "${TMP}/snapshot/systemd/"
# 3) Tests + service scripts
mkdir -p "${TMP}/snapshot/scripts/tests" "${TMP}/snapshot/scripts/service"
cp -a "${TESTDIR}" "${TMP}/snapshot/scripts/tests/gateway"
cp -a "${SRVDIR}"  "${TMP}/snapshot/scripts/service/api-gateway"
# 4) Logs (tail a few for forensics)
mkdir -p "${TMP}/snapshot/logs"
find "${LOGDIR}" -type f -name "gw-smoke-*.log" -printf "%T@ %p\n" 2>/dev/null \
 | sort -nr | head -3 | awk '{print $2}' | xargs -r -I{} cp -a "{}" "${TMP}/snapshot/logs/" || true
# 5) Python env & litellm version
mkdir -p "${TMP}/snapshot/env"
python3 -m pip freeze > "${TMP}/snapshot/env/pip-freeze.txt" || true
python3 - <<'PY' > "${TMP}/snapshot/env/litellm-version.txt" || true
try:
    import importlib.metadata as md
    print(md.version("litellm"))
except Exception as e:
    print(f"unknown ({e})")
PY
# 6) Live API manifest (models)
mkdir -p "${TMP}/snapshot/runtime"
curl -fsS -H "Authorization: Bearer ${MASTER_KEY}" \
     -H "Content-Type: application/json" \
     "${API_URL}/v1/models" \
     -o "${TMP}/snapshot/runtime/models.json" || true

# 7) Checksums
( cd "${TMP}/snapshot" && find . -type f -print0 | xargs -0 sha256sum ) > "${TMP}/snapshot/sha256sums.txt"

# 8) Pack
mkdir -p "${BKDIR}"
tar -C "${TMP}" -czf "${OUT}" snapshot
echo "✅ Checkpoint created: ${OUT}"

# 9) Validation: list contents
tar -tzf "${OUT}" | head -20
echo "Validation: archive is readable. Done."
