#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY creates missing configuration files
echo "=== [Config Creator] Creating Missing Configuration Files ==="

BASE="/opt/HX-Infrastructure-/api-gateway"
TEST_DIR="${BASE}/scripts/tests/gateway"
CFG_DIR="${TEST_DIR}/config"

# Preflight check
if [[ ! -d "$TEST_DIR" ]]; then
    echo "❌ Test directory not found: $TEST_DIR"
    echo "   Please run Phase 1 (install_smoke_tests.sh) first"
    exit 1
fi

# Defensively ensure base directory hierarchy exists
sudo mkdir -p "$BASE"

# Create config directory if missing
sudo mkdir -p "$CFG_DIR"

# Create smoke_suite.sh (environment configuration)
echo "→ Creating config/smoke_suite.sh..."
sudo tee "$CFG_DIR/smoke_suite.sh" >/dev/null <<'EOF'
# Environment used by nightly_runner.sh (SOLID: Dependency Inversion)
export GW_HOST="${GW_HOST:-127.0.0.1}"
export GW_PORT="${GW_PORT:-4000}"
export API="${API:-http://${GW_HOST}:${GW_PORT}}"
export MASTER_KEY="${MASTER_KEY:-REPLACE_WITH_ACTUAL_KEY}"
export LOG_DIR="${LOG_DIR:-/opt/HX-Infrastructure-/api-gateway/logs/services/gateway}"
EOF

sudo chmod 644 "$CFG_DIR/smoke_suite.sh"

echo "✅ Configuration files created successfully"
echo "Created: $CFG_DIR/smoke_suite.sh"
