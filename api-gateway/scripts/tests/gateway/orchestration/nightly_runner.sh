#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY handles systemd-triggered execution
BASE="/opt/HX-Infrastructure-/api-gateway"
TEST_DIR="${BASE}/scripts/tests/gateway"

# Load environment configuration (Dependency Inversion)
source "${TEST_DIR}/config/smoke_suite.sh"

# Export for sub-processes
export API MASTER_KEY LOG_DIR

# Execute the existing smoke suite orchestrator
exec "${TEST_DIR}/orchestration/smoke_suite.sh"
