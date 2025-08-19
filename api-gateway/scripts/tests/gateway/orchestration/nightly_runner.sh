#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY handles scheduled execution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration (preserving SCRIPT_DIR)
ORCHESTRATION_DIR="$SCRIPT_DIR"
source "${SCRIPT_DIR}/../config/test_config.sh"

RUNNER_NAME="gateway_nightly_runner"

# Logging with dynamic timestamp
log_runner() {
    local current_time
    current_time="$(date -u +%Y%m%dT%H%M%SZ)"
    echo "[${current_time}] ${RUNNER_NAME}: $1"
}

log_runner "Starting nightly smoke test execution"
log_runner "Working directory: $(pwd)"
log_runner "API Gateway: ${API_BASE}"

# Execute the smoke suite
if "${ORCHESTRATION_DIR}/smoke_suite.sh"; then
    log_runner "✅ Nightly smoke tests completed successfully"
    exit 0
else
    log_runner "❌ Nightly smoke tests failed"
    exit 1
fi
