#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY updates systemd unit configuration
echo "=== [Systemd Updater] Configuring Service Unit ==="

BASE="/opt/HX-Infrastructure-/api-gateway"
SVC="hx-gateway-smoke.service"
UNIT="/etc/systemd/system/${SVC}"

# Preflight check
if [[ ! -f "$UNIT" ]]; then
    echo "❌ Systemd unit not found: $UNIT"
    echo "   Please run Phase 2 (setup_systemd.sh) first"
    exit 1
fi

echo "→ Updating WorkingDirectory in systemd unit..."
if sudo grep -q -E '^[[:space:]]*WorkingDirectory=' "$UNIT"; then
    # Replace the first existing WorkingDirectory entry (with optional leading whitespace)
    sudo sed -i -E '0,/^[[:space:]]*WorkingDirectory=/s|^[[:space:]]*WorkingDirectory=.*|WorkingDirectory='${BASE}'|' "$UNIT"
    echo "   Updated existing WorkingDirectory to: ${BASE}"
else
    # No WorkingDirectory found, insert after [Service] header
    sudo sed -i "/^\[Service\]/a WorkingDirectory=${BASE}" "$UNIT"
    echo "   Added WorkingDirectory to: ${BASE}"
fi

echo "→ Updating ExecStart path in systemd unit..."
TARGET="${BASE}/scripts/tests/gateway/orchestration/nightly_runner.sh"
if sudo grep -qE '^[[:space:]]*ExecStart=' "$UNIT"; then
    if ! sudo grep -qE "^[[:space:]]*ExecStart=.*nightly_runner\.sh" "$UNIT"; then
        sudo sed -E -i "s|^[[:space:]]*ExecStart=.*|ExecStart=/usr/bin/env bash -lc '${TARGET}'|" "$UNIT"
        echo "   Updated ExecStart path"
    else
        echo "   ExecStart path already correct"
    fi
else
    sudo sed -i "/^\[Service\]/a ExecStart=/usr/bin/env bash -lc '${TARGET}'" "$UNIT"
    echo "   Inserted ExecStart"
fi

echo "→ Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "✅ Systemd unit configuration updated successfully"
echo "Unit: ${UNIT}"
echo "Working Directory: ${BASE}"
