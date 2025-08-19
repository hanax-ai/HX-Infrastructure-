# Environment used by nightly_runner.sh (SOLID: Dependency Inversion)
export GW_HOST="${GW_HOST:-192.168.10.39}"
export GW_PORT="${GW_PORT:-4000}"
export API="${API:-http://${GW_HOST}:${GW_PORT}}"
export MASTER_KEY="${MASTER_KEY:-}"
export LOG_DIR="${LOG_DIR:-/opt/HX-Infrastructure-/api-gateway/logs/services/gateway}"

# Security guard - require MASTER_KEY to be set externally
if [[ -z "$MASTER_KEY" ]]; then
    echo "ERROR: MASTER_KEY environment variable must be set" >&2
    echo "   Please export MASTER_KEY=your_api_key before sourcing this config" >&2
    echo "   This prevents accidental use of hardcoded credentials" >&2
    exit 1
fi
