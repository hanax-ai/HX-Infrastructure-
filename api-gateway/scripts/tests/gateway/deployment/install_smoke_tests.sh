#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY installs smoke test infrastructure
# Phase 1: Gateway Smoke Test Installation

echo "=== [Phase 1] Installing Gateway Smoke Test Infrastructure ==="

# Configuration - Environment variables with fallbacks (SOLID: Dependency Inversion)
BASE_DIR="${BASE_DIR:-/opt/HX-Infrastructure-/api-gateway}"
TEST_DIR="${BASE_DIR}/scripts/tests/gateway"
LOG_DIR="${BASE_DIR}/logs/services/gateway"

# Preflight checks
echo "→ Preflight dependency checks..."
for bin in curl jq bash date; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "❌ Missing required binary: $bin"
        exit 1
    fi
done
echo "✅ All dependencies available"

# Create SOLID-compliant directory structure
echo "→ Creating SOLID directory structure..."
sudo mkdir -p "${TEST_DIR}"/{core,orchestration,deployment,config}
sudo mkdir -p "${LOG_DIR}"
echo "✅ Directory structure created"

# Install configuration files (SOLID: Dependency Inversion Principle)
echo "→ Installing configuration files..."

sudo tee "${TEST_DIR}/config/gateway.env" >/dev/null <<'EOF'
# Gateway Configuration - Environment Variables (SOLID: Dependency Inversion)
# Override these values in your environment as needed

# Gateway Connection
GW_HOST="${GW_HOST:-192.168.10.39}"
GW_PORT="${GW_PORT:-4000}"
API_BASE="${API_BASE:-http://${GW_HOST}:${GW_PORT}}"
MASTER_KEY="${MASTER_KEY:-sk-hx-dev-1234}"

# Backend Servers (for routing tests)
LLM01_IP="${LLM01_IP:-192.168.10.29}"
LLM02_IP="${LLM02_IP:-192.168.10.28}"
ORC_IP="${ORC_IP:-192.168.10.31}"

# Test Configuration
TIMEOUT="${TIMEOUT:-30}"
MAX_TOKENS="${MAX_TOKENS:-10}"
TEMPERATURE="${TEMPERATURE:-0}"

# Logging
LOG_DIR="${LOG_DIR:-/opt/HX-Infrastructure-/api-gateway/logs/services/gateway}"
EOF

sudo tee "${TEST_DIR}/config/test_config.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
# Test Configuration Helper (SOLID: Dependency Inversion)

# Load environment configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/gateway.env"

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
EOF

echo "✅ Configuration files installed"

# Install core test components (SOLID: Single Responsibility Principle)
echo "→ Installing core test components..."

# Models test - SOLID: Single Responsibility (only tests /v1/models)
sudo tee "${TEST_DIR}/core/models_test.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY tests /v1/models endpoint
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/test_config.sh"

TEST_NAME="models_test"
log_test "$TEST_NAME" "Testing /v1/models endpoint"

# Test /v1/models endpoint
response=$(make_request "/v1/models" "")

# Validate response structure
model_count=$(echo "$response" | jq -r '.data | length')

if [[ "$model_count" -gt 0 ]]; then
    models=$(echo "$response" | jq -r '.data[].id' | tr '\n' ' ')
    log_test "$TEST_NAME" "✅ SUCCESS: Found $model_count models: $models"
    exit 0
else
    log_test "$TEST_NAME" "❌ FAIL: No models found in response"
    exit 1
fi
EOF

# Embeddings test - SOLID: Single Responsibility (only tests /v1/embeddings)
sudo tee "${TEST_DIR}/core/embeddings_test.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY tests /v1/embeddings endpoint
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/test_config.sh"

TEST_NAME="embeddings_test"
log_test "$TEST_NAME" "Testing /v1/embeddings endpoint"

# Test each embedding model with expected dimensions
check_embedding_model() {
    local model="$1"
    local expected_dim="$2"
    
    log_test "$TEST_NAME" "Testing $model (expecting $expected_dim dimensions)"
    
    local payload="{\"model\":\"$model\",\"input\":\"HX Infrastructure test\"}"
    local response=$(make_request "/v1/embeddings" "$payload")
    
    local actual_dim=$(echo "$response" | jq -r '.data[0].embedding | length')
    
    if [[ "$actual_dim" == "$expected_dim" ]]; then
        log_test "$TEST_NAME" "✅ $model: $actual_dim dimensions (correct)"
        return 0
    else
        log_test "$TEST_NAME" "❌ $model: Expected $expected_dim, got $actual_dim dimensions"
        return 1
    fi
}

# Test all embedding models
failed=0
check_embedding_model "emb-premium" "1024" || ((failed++))
check_embedding_model "emb-perf" "768" || ((failed++))
check_embedding_model "emb-light" "384" || ((failed++))

if [[ $failed -eq 0 ]]; then
    log_test "$TEST_NAME" "✅ SUCCESS: All embedding models working correctly"
    exit 0
else
    log_test "$TEST_NAME" "❌ FAIL: $failed embedding model(s) failed"
    exit 1
fi
EOF

# Chat test - SOLID: Single Responsibility (only tests /v1/chat/completions)
sudo tee "${TEST_DIR}/core/chat_test.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY tests /v1/chat/completions endpoint
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/test_config.sh"

TEST_NAME="chat_test"
log_test "$TEST_NAME" "Testing /v1/chat/completions endpoint"

# Test deterministic chat response
test_chat_model() {
    local model="$1"
    
    log_test "$TEST_NAME" "Testing chat with $model"
    
    local payload="{
        \"model\":\"$model\",
        \"messages\":[{\"role\":\"user\",\"content\":\"Return exactly the text: HX-OK\"}],
        \"max_tokens\":${MAX_TOKENS},
        \"temperature\":${TEMPERATURE}
    }"
    
    local response=$(make_request "/v1/chat/completions" "$payload")
    local content=$(echo "$response" | jq -r '.choices[0].message.content')
    
    if echo "$content" | grep -q "HX-OK"; then
        log_test "$TEST_NAME" "✅ $model: Response contains expected text"
        return 0
    else
        log_test "$TEST_NAME" "❌ $model: Expected 'HX-OK', got: $content"
        return 1
    fi
}

# Test primary chat model
if test_chat_model "hx-chat"; then
    log_test "$TEST_NAME" "✅ SUCCESS: Chat completions working correctly"
    exit 0
else
    log_test "$TEST_NAME" "❌ FAIL: Chat completions test failed"
    exit 1
fi
EOF

# Routing test - SOLID: Single Responsibility (only tests model routing)
sudo tee "${TEST_DIR}/core/routing_test.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY tests model routing functionality
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/test_config.sh"

TEST_NAME="routing_test"
log_test "$TEST_NAME" "Testing model routing across backends"

# Models to test routing for (covering all backend servers)
declare -a routing_models=(
    "llm01-llama3.2-3b"    # LLM-01 server
    "llm02-phi3"           # LLM-02 server  
    "llm02-gemma2-2b"      # LLM-02 server
    "hx-chat"              # Load balancer group
)

test_model_routing() {
    local model="$1"
    
    log_test "$TEST_NAME" "Testing routing for $model"
    
    local payload="{
        \"model\":\"$model\",
        \"messages\":[{\"role\":\"user\",\"content\":\"Return exactly the text: HX-OK\"}],
        \"max_tokens\":${MAX_TOKENS},
        \"temperature\":${TEMPERATURE}
    }"
    
    local response=$(make_request "/v1/chat/completions" "$payload")
    local content=$(echo "$response" | jq -r '.choices[0].message.content')
    
    if echo "$content" | grep -q "HX-OK"; then
        log_test "$TEST_NAME" "✅ $model: Routing successful"
        return 0
    else
        log_test "$TEST_NAME" "❌ $model: Routing failed - got: $content"
        return 1
    fi
}

# Test routing for all models
failed=0
for model in "${routing_models[@]}"; do
    test_model_routing "$model" || ((failed++))
done

if [[ $failed -eq 0 ]]; then
    log_test "$TEST_NAME" "✅ SUCCESS: All model routing working correctly"
    exit 0
else
    log_test "$TEST_NAME" "❌ FAIL: $failed model routing(s) failed"
    exit 1
fi
EOF

echo "✅ Core test components installed"

# Make all scripts executable
echo "→ Setting executable permissions..."
sudo chmod +x "${TEST_DIR}/config/test_config.sh"
sudo chmod +x "${TEST_DIR}/core"/*.sh
echo "✅ Executable permissions set"

# Validation
echo "→ Validating installation..."
echo "Directory structure:"
tree "${TEST_DIR}" 2>/dev/null || ls -la "${TEST_DIR}"

echo
echo "=== [Phase 1] Installation Complete ✅ ==="
echo "Location: ${TEST_DIR}"
echo "Components installed:"
echo "  - Configuration: gateway.env, test_config.sh"
echo "  - Core tests: models_test.sh, embeddings_test.sh, chat_test.sh, routing_test.sh"
echo "  - Log directory: ${LOG_DIR}"
echo
echo "Next: Run Phase 2 (setup_systemd.sh) to configure scheduling"
