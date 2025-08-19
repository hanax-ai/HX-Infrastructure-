#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Test Configuration Helper (SOLID: Dependency Inversion)

# Load environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verify gateway.env exists before sourcing
if [[ ! -f "${SCRIPT_DIR}/gateway.env" ]] || [[ ! -r "${SCRIPT_DIR}/gateway.env" ]]; then
    echo "ERROR: Gateway environment file not found or not readable: ${SCRIPT_DIR}/gateway.env" >&2
    exit 1
fi

source "${SCRIPT_DIR}/gateway.env"

# Validate critical environment variables
if [[ -z "${GW_HOST:-}" ]]; then
    echo "ERROR: GW_HOST is required" >&2
    exit 1
fi

if [[ -z "${GW_PORT:-}" ]]; then
    echo "ERROR: GW_PORT is required" >&2
    exit 1
fi

if [[ -z "${MASTER_KEY:-}" ]]; then
    echo "ERROR: MASTER_KEY is required" >&2
    exit 1
fi

# Set safe defaults for optional variables
TIMEOUT="${TIMEOUT:-30}"
MAX_TOKENS="${MAX_TOKENS:-10}"
TEMPERATURE="${TEMPERATURE:-0}"
LOG_DIR="${LOG_DIR:-/opt/HX-Infrastructure-/api-gateway/logs/services/gateway}"

# Export resolved variables for test scripts
export API_BASE="http://${GW_HOST}:${GW_PORT}"
export MASTER_KEY
export TIMEOUT
export MAX_TOKENS
export TEMPERATURE
export LOG_DIR

# Common test functions
log_test() {
    local test_name="$1"
    local message="$2"
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ${test_name}: ${message}"
}

make_request() {
    local endpoint="$1"
    local data="$2"
    
    curl -fsS \
        --max-time "${TIMEOUT}" \
        -H "Authorization: Bearer ${MASTER_KEY}" \
        -H "Content-Type: application/json" \
        "${API_BASE}${endpoint}" \
        ${data:+-d "$data"}
}
