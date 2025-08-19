#!/usr/bin/env bash
set -euo pipefail
BASE="/opt/HX-Infrastructure-/api-gateway"
BKDIR="${BASE}/gateway/backups"
LOGDIR="${BASE}/logs/services/gateway"
TESTDIR="${BASE}/scripts/tests/gateway"
SRVDIR="${BASE}/scripts/service/api-gateway"
SVC_GW="hx-litellm-gateway.service"
SVC_SMOKE="hx-gateway-smoke.service"
TIMER_SMOKE="hx-gateway-smoke.timer"

# SUDO helper for consistent privilege usage - empty when running as root
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    SUDO=""
else
    SUDO="${SUDO:-sudo}"
fi

# Preflight checks for required commands
for cmd in systemctl tar find rsync; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Required command not found: $cmd" >&2
        exit 1
    fi
done

ARCHIVE="${1:-}"
if [ -z "${ARCHIVE}" ]; then
  # pick newest
  ARCHIVE="$(find "${BKDIR}" -type f -name 'gw-checkpoint-*.tgz' -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -1 | awk '{print $2}')"
  
  # Check for specific error conditions when no archive was found
  if [ -z "${ARCHIVE}" ]; then
    if [ -d "${BKDIR}" ]; then
      echo "❌ No archives found in BKDIR: ${BKDIR}" >&2
    else
      echo "❌ BKDIR not found: ${BKDIR}" >&2
    fi
    exit 1
  fi
fi
[ -f "${ARCHIVE}" ] || { echo "❌ Archive not found: ${ARCHIVE:-<none>}"; exit 1; }

TS="$(date -u +%Y%m%dT%H%M%SZ)"
PRE="${BKDIR}/pre-restore-${TS}.tgz"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
echo "=== [restore_checkpoint] Using archive: ${ARCHIVE}"

# 0) Safety backup of current state
echo "--> Backing up current state to ${PRE}"
tar -C "${BASE}" -czf "${PRE}" \
  config/api-gateway \
  scripts/tests/gateway \
  scripts/service/api-gateway || true
tar -czf "${PRE}.systemd.tgz" \
  /etc/systemd/system/${SVC_GW} \
  /etc/systemd/system/${SVC_SMOKE} \
  /etc/systemd/system/${TIMER_SMOKE} || true
echo "Backup complete."

# 1) Stop services
echo "Executing: Stop ${SVC_GW}"
${SUDO} systemctl stop "${SVC_GW}" || true
sleep 5
if ! ${SUDO} systemctl is-active --quiet "${SVC_GW}"; then echo "Ollama gateway stopped successfully!"; else echo "ERROR: gateway failed to stop." >&2; exit 1; fi
${SUDO} systemctl stop "${TIMER_SMOKE}" "${SVC_SMOKE}" || true

# 2) Extract archive to temp
tar -C "${TMP}" -xzf "${ARCHIVE}"
SNAP="${TMP}/snapshot"

# 3) Restore configs/scripts
echo "--> Restoring config + scripts"
${SUDO} mkdir -p "${BASE}/config" "${BASE}/scripts/tests" "${BASE}/scripts/service"
${SUDO} rsync -a "${SNAP}/config/api-gateway/" "${BASE}/config/api-gateway/"
${SUDO} rsync -a "${SNAP}/scripts/tests/gateway/" "${BASE}/scripts/tests/gateway/"
${SUDO} rsync -a "${SNAP}/scripts/service/api-gateway/" "${BASE}/scripts/service/api-gateway/"

# 4) Restore systemd units
echo "--> Restoring systemd units"
${SUDO} rsync -a "${SNAP}/systemd/" /etc/systemd/system/
${SUDO} systemctl daemon-reload

# 5) Permissions (least privilege)
if id hx-gateway >/dev/null 2>&1; then
  ${SUDO} chown -R hx-gateway:hx-gateway "${BASE}/scripts/tests/gateway" "${LOGDIR}" || true
  ${SUDO} find "${BASE}/scripts/tests/gateway" -type f -name "*.sh" -exec ${SUDO} chmod 755 {} \; || true
  ${SUDO} chmod 755 "${LOGDIR}" || true
fi

# 6) Start services with HX confirmation
echo "Executing: Start ${SVC_GW}"
${SUDO} systemctl enable "${SVC_GW}" --now
sleep 5
if ${SUDO} systemctl is-active --quiet "${SVC_GW}"; then echo "Gateway enabled and started successfully!"; else echo "ERROR: gateway failed to enable/start." >&2; exit 1; fi

${SUDO} systemctl enable "${TIMER_SMOKE}" --now || true

# 7) Final validation – run orchestrator once
API="http://127.0.0.1:4000" # Security: MASTER_KEY must be set externally
if [[ -z "${MASTER_KEY:-}" ]]; then
    echo "❌ ERROR: MASTER_KEY environment variable is required" >&2
    echo "   Please export MASTER_KEY=your-secure-key before running this script" >&2
    exit 1
fi LOG_DIR="${LOGDIR}" \
  "${BASE}/scripts/tests/gateway/orchestration/smoke_suite.sh"

echo "✅ Restore completed and validated."
