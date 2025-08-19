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
if ! sudo grep -q "^WorkingDirectory=${BASE}$" "$UNIT"; then
    sudo sed -i "s|^WorkingDirectory=.*|WorkingDirectory=${BASE}|g" "$UNIT" || true
    if ! sudo grep -q "^WorkingDirectory=" "$UNIT"; then
        sudo sed -i "/^\[Service\]/a WorkingDirectory=${BASE}" "$UNIT"
    fi
    echo "   Updated WorkingDirectory to: ${BASE}"
else
    echo "   WorkingDirectory already correct"
fi

echo "→ Updating ExecStart path in systemd unit..."
if ! sudo grep -q "scripts/tests/gateway/orchestration/nightly_runner.sh" "$UNIT"; then
    sudo sed -i "s|^ExecStart=.*|ExecStart=/usr/bin/env bash -lc 'scripts/tests/gateway/orchestration/nightly_runner.sh'|g" "$UNIT"
    echo "   Updated ExecStart path"
else
    echo "   ExecStart path already correct"
fi

echo "→ Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "✅ Systemd unit configuration updated successfully"
echo "Unit: ${UNIT}"
echo "Working Directory: ${BASE}"
