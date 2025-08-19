#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY creates orchestration runner
echo "=== [Orchestration Creator] Creating Systemd-Compatible Runner ==="

BASE="/opt/HX-Infrastructure-/api-gateway"
TEST_DIR="${BASE}/scripts/tests/gateway"
ORCH_DIR="${TEST_DIR}/orchestration"

# Preflight check
if [[ ! -d "$TEST_DIR" ]]; then
    echo "❌ Test directory not found: $TEST_DIR"
    exit 1
fi

if [[ ! -f "$TEST_DIR/config/smoke_suite.sh" ]]; then
    echo "❌ Configuration missing: $TEST_DIR/config/smoke_suite.sh"
    echo "   Please run create_config.sh first"
    exit 1
fi

# Create orchestration directory if missing
sudo mkdir -p "$ORCH_DIR"

# Create nightly_runner.sh (systemd-compatible orchestrator)
echo "→ Creating orchestration/nightly_runner.sh..."
sudo tee "$ORCH_DIR/nightly_runner.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY handles systemd-triggered execution
BASE="/opt/HX-Infrastructure-/api-gateway"
TEST_DIR="${BASE}/scripts/tests/gateway"

# Load and export all environment configuration (Dependency Inversion)
set -a
source "${TEST_DIR}/config/smoke_suite.sh"
set +a

# Execute the existing smoke suite orchestrator
exec "${TEST_DIR}/orchestration/smoke_suite.sh"
EOF

sudo chmod +x "$ORCH_DIR/nightly_runner.sh"

echo "✅ Orchestration runner created successfully"
echo "Created: $ORCH_DIR/nightly_runner.sh"
