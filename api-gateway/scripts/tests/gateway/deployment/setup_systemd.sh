#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY configures systemd scheduling infrastructure
# Phase 2: Gateway Smoke Test Systemd Setup

echo "=== [Phase 2] Setting up Systemd Timer & Service ==="

# Configuration - Environment variables with fallbacks (SOLID: Dependency Inversion)
BASE_DIR="${BASE_DIR:-/opt/HX-Infrastructure-/api-gateway}"
TEST_DIR="${BASE_DIR}/scripts/tests/gateway"
LOG_DIR="${BASE_DIR}/logs/services/gateway"
GW_HOST="${GW_HOST:-192.168.10.39}"
GW_PORT="${GW_PORT:-4000}"

# Require MASTER_KEY to be explicitly provided
if [[ -z "${MASTER_KEY:-}" ]]; then
    echo "❌ MASTER_KEY environment variable must be set"
    echo "   Please provide a secure API key for testing"
    echo "   Example: MASTER_KEY=your-secure-key $0"
    exit 1
fi

# Preflight checks
echo "→ Preflight checks..."
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root (for systemd unit installation)"
    exit 1
fi

if [[ ! -d "$TEST_DIR" ]]; then
    echo "❌ Test directory not found: $TEST_DIR"
    echo "   Please run Phase 1 (install_smoke_tests.sh) first"
    exit 1
fi

if [[ ! -f "$TEST_DIR/core/models_test.sh" ]]; then
    echo "❌ Core test components not found"
    echo "   Please run Phase 1 (install_smoke_tests.sh) first"
    exit 1
fi

if [[ ! -f "${SCRIPT_DIR}/../config/test_config.sh" ]]; then
    echo "❌ test_config.sh not found — please run Phase 1 (install_smoke_tests.sh) or ensure ../config/test_config.sh is present"
    exit 1
fi

echo "✅ Preflight checks passed"

# Create orchestration script (SOLID: Single Responsibility - orchestration only)
echo "→ Installing orchestration script..."
tee "${TEST_DIR}/orchestration/smoke_suite.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY orchestrates test execution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/test_config.sh"

# Runtime guard - validate LOG_DIR before use to prevent writing to root
if [[ -z "${LOG_DIR:-}" ]]; then
    echo "❌ ERROR: LOG_DIR is not set or empty" >&2
    echo "   Check test_config.sh configuration or set LOG_DIR environment variable" >&2
    exit 1
fi

# Ensure log directory is writable
if ! mkdir -p "${LOG_DIR}" 2>/dev/null; then
    echo "❌ ERROR: Cannot create log directory: ${LOG_DIR}" >&2
    echo "   Check permissions and disk space" >&2
    exit 1
fi

if [[ ! -w "${LOG_DIR}" ]]; then
    echo "❌ ERROR: Log directory is not writable: ${LOG_DIR}" >&2
    echo "   Check directory permissions" >&2
    exit 1
fi

SUITE_NAME="gateway_smoke_suite"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="${LOG_DIR}/gw-smoke-${TIMESTAMP}.log"

# Log directory validated and ready

# Test execution function
run_test() {
    local test_name="$1"
    local test_script="${SCRIPT_DIR}/../core/${test_name}.sh"
    
    echo "--- Testing: $test_name ---" | tee -a "${LOG_FILE}"
    
    if [[ ! -x "$test_script" ]]; then
        echo "❌ Test script not executable: $test_script" | tee -a "${LOG_FILE}"
        return 1
    fi
    
    if timeout 60 "$test_script" 2>&1 | tee -a "${LOG_FILE}"; then
        echo "✅ PASS: $test_name" | tee -a "${LOG_FILE}"
        return 0
    else
        echo "❌ FAIL: $test_name" | tee -a "${LOG_FILE}"
        return 1
    fi
}

# Main execution
echo "=== Gateway Smoke Test Suite @ ${TIMESTAMP} ===" | tee "${LOG_FILE}"
echo "API Gateway: http://${GW_HOST}:${GW_PORT}" | tee -a "${LOG_FILE}"
echo "Log File: ${LOG_FILE}" | tee -a "${LOG_FILE}"
echo | tee -a "${LOG_FILE}"

# Core test execution order
declare -a tests=("models_test" "embeddings_test" "chat_test" "routing_test")
failed_tests=0

for test in "${tests[@]}"; do
    if ! run_test "$test"; then
        ((failed_tests++))
    fi
    echo | tee -a "${LOG_FILE}"
done

# Final results
echo "=== Test Suite Results ===" | tee -a "${LOG_FILE}"
echo "Total Tests: ${#tests[@]}" | tee -a "${LOG_FILE}"
echo "Failed Tests: $failed_tests" | tee -a "${LOG_FILE}"
echo "Success Rate: $(( (${#tests[@]} - failed_tests) * 100 / ${#tests[@]} ))%" | tee -a "${LOG_FILE}"

if [[ $failed_tests -eq 0 ]]; then
    echo "🎉 ALL TESTS PASSED ✅" | tee -a "${LOG_FILE}"
    exit 0
else
    echo "⚠️  SOME TESTS FAILED ❌" | tee -a "${LOG_FILE}"
    exit 1
fi
EOF

chmod +x "${TEST_DIR}/orchestration/smoke_suite.sh"
echo "✅ Orchestration script installed"

# Create nightly runner script (SOLID: Single Responsibility - scheduled execution only)
echo "→ Installing nightly runner script..."
tee "${TEST_DIR}/orchestration/nightly_runner.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY handles scheduled execution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
source "${SCRIPT_DIR}/../config/test_config.sh"

RUNNER_NAME="gateway_nightly_runner"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

# Logging with timestamp
log_runner() {
    echo "[${TIMESTAMP}] ${RUNNER_NAME}: $1"
}

log_runner "Starting nightly smoke test execution"
log_runner "Working directory: $(pwd)"
log_runner "API Gateway: ${API_BASE}"

# Execute the smoke suite
if "${SCRIPT_DIR}/smoke_suite.sh"; then
    log_runner "✅ Nightly smoke tests completed successfully"
    exit 0
else
    log_runner "❌ Nightly smoke tests failed"
    exit 1
fi
EOF

chmod +x "${TEST_DIR}/orchestration/nightly_runner.sh"
echo "✅ Nightly runner script installed"

# Install systemd service unit (SOLID: Single Responsibility - service definition only)
echo "→ Installing systemd service unit..."
tee /etc/systemd/system/hx-gateway-smoke.service >/dev/null <<EOF
[Unit]
Description=HX API Gateway Nightly Smoke Tests
Documentation=file://${TEST_DIR}/README.md
After=network-online.target hx-litellm-gateway.service
Wants=network-online.target
Requires=hx-litellm-gateway.service

[Service]
Type=oneshot
User=hx-gateway
Group=hx-gateway
Environment=GW_HOST=${GW_HOST}
Environment=GW_PORT=${GW_PORT}
Environment=API_BASE=http://${GW_HOST}:${GW_PORT}
Environment=MASTER_KEY=${MASTER_KEY}
Environment=LOG_DIR=${LOG_DIR}
ExecStart=${TEST_DIR}/orchestration/nightly_runner.sh
WorkingDirectory=${TEST_DIR}
StandardOutput=journal
StandardError=journal
TimeoutStartSec=300
Nice=5

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
EOF

echo "✅ Systemd service unit installed"

# Install systemd timer unit (SOLID: Single Responsibility - scheduling only)
echo "→ Installing systemd timer unit..."
tee /etc/systemd/system/hx-gateway-smoke.timer >/dev/null <<'EOF'
[Unit]
Description=Schedule HX API Gateway Nightly Smoke Tests
Documentation=man:systemd.timer(5)

[Timer]
# Run at 00:05 AM every day
OnCalendar=*-*-* 00:05:00
# Add randomized delay to prevent system load spikes
RandomizedDelaySec=300
# Persist timer state across reboots
Persistent=true
# Ensure accuracy for monitoring
AccuracySec=1min
# Reference the service unit
Unit=hx-gateway-smoke.service

[Install]
WantedBy=timers.target
EOF

echo "✅ Systemd timer unit installed"

# Configure logging infrastructure
echo "→ Setting up logging infrastructure..."

# Create log rotation configuration
tee /etc/logrotate.d/hx-gateway-smoke >/dev/null <<EOF
${LOG_DIR}/gw-smoke-*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 hx-gateway hx-gateway
    sharedscripts
}
EOF

# Ensure proper permissions
chown -R hx-gateway:hx-gateway "${LOG_DIR}" 2>/dev/null || true
chmod 755 "${LOG_DIR}" 2>/dev/null || true

echo "✅ Logging infrastructure configured"

# Reload systemd and enable services
echo "→ Configuring systemd services..."
systemctl daemon-reload

# Enable and start the timer
systemctl enable --now hx-gateway-smoke.timer

echo "✅ Systemd services configured and enabled"

# Validation
echo "→ Validating systemd configuration..."

# Check timer status
if systemctl is-active --quiet hx-gateway-smoke.timer; then
    echo "✅ Timer is active"
else
    echo "❌ Timer is not active"
    exit 1
fi

# Show timer schedule
echo "Timer schedule:"
systemctl list-timers hx-gateway-smoke.timer --no-pager

# Test service (dry run)
echo "→ Testing service configuration (dry run)..."
if systemctl --dry-run start hx-gateway-smoke.service >/dev/null 2>&1; then
    echo "✅ Service configuration valid"
else
    echo "❌ Service configuration invalid"
    exit 1
fi

echo
echo "=== [Phase 2] Systemd Setup Complete ✅ ==="
echo "Services installed:"
echo "  - hx-gateway-smoke.service (oneshot execution)"
echo "  - hx-gateway-smoke.timer (nightly at 00:05 UTC)"
echo "Logging:"
echo "  - Logs: ${LOG_DIR}/gw-smoke-YYYYMMDDTHHMMSSZ.log"
echo "  - Rotation: 30 days retention with compression"
echo "Commands:"
echo "  - Manual execution: systemctl start hx-gateway-smoke.service"
echo "  - Check timer: systemctl status hx-gateway-smoke.timer"
echo "  - View logs: journalctl -u hx-gateway-smoke.service"
echo
echo "Next: Run Phase 3 (smoke_suite.sh) for immediate testing"
