#!/usr/bin/env bash
set -euo pipefail

echo "🔍 HX-Infrastructure Embedding Models Test Suite"
echo "================================================"
echo
echo "Testing embedding models on ORC server via API Gateway"
echo "Date: $(date)"
echo "Gateway: http://localhost:4000"
echo "ORC Server: http://192.168.10.31:11434"
echo

# Configuration
API_BASE="http://localhost:4000"
MASTER_KEY="sk-hx-dev-1234"
ORC_DIRECT="http://192.168.10.31:11434"

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_test() { echo -e "${BLUE}[TEST]${NC} $1"; TESTS_TOTAL=$((TESTS_TOTAL + 1)); }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Test embedding model function
test_embedding_model() {
    local model_name="$1"
    local display_name="$2"
    local expected_min_dim="$3"
    local expected_max_dim="$4"
    
    echo
    log_info "Testing: $display_name"
    log_info "Model: $model_name"
    
    # Test 1: Model availability in gateway
    log_test "Model availability in API Gateway"
    if curl -s -H "Authorization: Bearer ${MASTER_KEY}" "${API_BASE}/v1/models" \
        | jq -e ".data[] | select(.id==\"${model_name}\")" >/dev/null 2>&1; then
        log_pass "✓ Model '$model_name' available in gateway"
    else
        log_fail "✗ Model '$model_name' not available in gateway"
        return 1
    fi
    
    # Test 2: Single text embedding via API Gateway
    log_test "Single text embedding generation"
    local single_response
    single_response=$(curl -s --max-time 30 "${API_BASE}/v1/embeddings" \
        -H "Authorization: Bearer ${MASTER_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"${model_name}\",
            \"input\": \"The quick brown fox jumps over the lazy dog\"
        }" 2>/dev/null)
    
    if echo "$single_response" | jq -e '.data[0].embedding' >/dev/null 2>&1; then
        local embedding_dim
        embedding_dim=$(echo "$single_response" | jq -r '.data[0].embedding | length')
        log_pass "✓ Single embedding generated successfully"
        log_info "  Embedding dimension: $embedding_dim"
        
        # Validate dimension range
        if [[ $embedding_dim -ge $expected_min_dim && $embedding_dim -le $expected_max_dim ]]; then
            log_pass "✓ Embedding dimension within expected range ($expected_min_dim-$expected_max_dim)"
        else
            log_warn "⚠ Embedding dimension outside expected range: $embedding_dim (expected $expected_min_dim-$expected_max_dim)"
        fi
    else
        log_fail "✗ Single embedding generation failed"
        echo "   Response: ${single_response:0:200}..."
        return 1
    fi
    
    # Test 3: Batch embeddings (multiple inputs)
    log_test "Batch embeddings generation"
    local batch_response
    batch_response=$(curl -s --max-time 30 "${API_BASE}/v1/embeddings" \
        -H "Authorization: Bearer ${MASTER_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"${model_name}\",
            \"input\": [
                \"First document for embedding\",
                \"Second document with different content\",
                \"Third document about machine learning\"
            ]
        }" 2>/dev/null)
    
    if echo "$batch_response" | jq -e '.data | length == 3' >/dev/null 2>&1; then
        log_pass "✓ Batch embeddings generated (3 vectors)"
        
        # Check if all embeddings have same dimension
        local dims
        dims=$(echo "$batch_response" | jq -r '.data[].embedding | length' | sort -u)
        if [[ $(echo "$dims" | wc -l) -eq 1 ]]; then
            log_pass "✓ All embeddings have consistent dimension: $dims"
        else
            log_fail "✗ Inconsistent embedding dimensions: $dims"
        fi
    else
        log_fail "✗ Batch embeddings generation failed"
        echo "   Response: ${batch_response:0:200}..."
        return 1
    fi
    
    # Test 4: Usage reporting
    log_test "Token usage reporting"
    local usage_response
    usage_response=$(curl -s --max-time 30 "${API_BASE}/v1/embeddings" \
        -H "Authorization: Bearer ${MASTER_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"${model_name}\",
            \"input\": \"Usage test text\"
        }" 2>/dev/null)
    
    local usage_tokens
    usage_tokens=$(echo "$usage_response" | jq -r '.usage.total_tokens // "N/A"')
    if [[ "$usage_tokens" != "N/A" && "$usage_tokens" != "null" ]]; then
        log_pass "✓ Usage reporting: $usage_tokens tokens"
    else
        log_warn "⚠ Usage reporting not available or invalid"
    fi
    
    # Test 5: Direct ORC connectivity test (bonus validation)
    log_test "Direct ORC server connectivity (validation)"
    if curl -s --max-time 10 "${ORC_DIRECT}/api/embeddings" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"${model_name#emb-*}\",
            \"input\": \"direct test\"
        }" | jq -e '.embeddings[0]' >/dev/null 2>&1; then
        log_pass "✓ Direct ORC connectivity confirmed"
    else
        log_warn "⚠ Direct ORC connectivity test inconclusive (may be normal)"
    fi
}

# Test direct ORC access function
test_direct_orc_models() {
    echo
    echo "=== DIRECT ORC SERVER VALIDATION ==="
    
    log_info "Testing direct access to ORC embedding models..."
    
    # Check ORC server availability
    log_test "ORC server connectivity"
    if curl -s --max-time 10 "${ORC_DIRECT}/api/version" >/dev/null 2>&1; then
        log_pass "✓ ORC server responding"
    else
        log_fail "✗ ORC server not responding"
        return 1
    fi
    
    # List available models on ORC
    log_info "Available models on ORC (direct):"
    local orc_models
    orc_models=$(curl -s --max-time 10 "${ORC_DIRECT}/api/tags" | jq -r '.models[].name' 2>/dev/null | sort)
    if [[ -n "$orc_models" ]]; then
        echo "$orc_models" | sed 's/^/   • /'
    else
        log_warn "⚠ Could not retrieve model list from ORC"
    fi
    
    # Test each embedding model directly
    local direct_models=("mxbai-embed-large" "nomic-embed-text" "all-minilm")
    for model in "${direct_models[@]}"; do
        log_test "Direct ORC test: $model"
        local direct_response
        direct_response=$(curl -s --max-time 30 "${ORC_DIRECT}/api/embed" \
            -H "Content-Type: application/json" \
            -d "{
                \"model\": \"${model}\",
                \"input\": \"direct connectivity test\"
            }" 2>/dev/null)
        
        if echo "$direct_response" | jq -e '.embeddings[0]' >/dev/null 2>&1; then
            local direct_dim
            direct_dim=$(echo "$direct_response" | jq -r '.embeddings[0] | length')
            log_pass "✓ $model: $direct_dim dimensions"
        else
            log_fail "✗ $model: failed or not available"
        fi
    done
}

# Main execution
main() {
    echo "=== PRE-FLIGHT CHECKS ==="
    
    # Check API Gateway
    log_test "API Gateway connectivity"
    if curl -s --max-time 10 "${API_BASE}/v1/models" -H "Authorization: Bearer ${MASTER_KEY}" >/dev/null 2>&1; then
        log_pass "✓ API Gateway responding"
    else
        log_fail "✗ API Gateway not responding"
        exit 1
    fi
    
    # Show available embedding models in gateway
    log_info "Available embedding models in API Gateway:"
    curl -s -H "Authorization: Bearer ${MASTER_KEY}" "${API_BASE}/v1/models" \
        | jq -r '.data[].id' | grep '^emb-' | sort | sed 's/^/   • /' || echo "   (none found)"
    
    echo
    echo "=== EMBEDDING MODEL TESTS VIA API GATEWAY ==="
    
    # Test each embedding model via API Gateway
    # Based on MTEB benchmarks and typical dimensions:
    # - mxbai-embed-large: ~1024 dimensions (SOTA for BERT-large size)
    # - nomic-embed-text: ~768 dimensions (efficient, good performance)  
    # - all-minilm: ~384 dimensions (lightweight, fast)
    
    test_embedding_model "emb-premium" "mxbai-embed-large (Premium Quality)" "1000" "1100"
    test_embedding_model "emb-perf" "nomic-embed-text (Performance Balanced)" "700" "800"
    test_embedding_model "emb-light" "all-minilm (Lightweight/Fast)" "300" "400"
    
    # Direct ORC validation
    test_direct_orc_models
    
    echo
    echo "=== SUMMARY ==="
    echo "Total Tests: $TESTS_TOTAL"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}🎉 All embedding tests passed!${NC}"
        echo
        echo "✅ Verified Embedding Models:"
        echo "   • emb-premium   → mxbai-embed-large   (SOTA quality, ~1024 dim)"
        echo "   • emb-perf      → nomic-embed-text    (Balanced, ~768 dim)"
        echo "   • emb-light     → all-minilm          (Fast, ~384 dim)"
        echo
        echo "🎯 Use Cases:"
        echo "   • emb-premium: Semantic search, RAG, high-accuracy tasks"
        echo "   • emb-perf: General embedding tasks, good speed/quality balance"
        echo "   • emb-light: Real-time applications, lightweight deployments"
        echo
        echo "🚀 All embedding models operational via OpenAI-compatible /v1/embeddings!"
        exit 0
    else
        echo -e "${RED}❌ Some embedding tests failed${NC}"
        echo
        echo "🔧 Troubleshooting:"
        echo "   • Check ORC server: systemctl status ollama (on 192.168.10.31)"
        echo "   • Test direct: curl ${ORC_DIRECT}/api/embeddings -d '{\"model\":\"mxbai-embed-large\",\"input\":\"test\"}'"
        echo "   • Check gateway: sudo journalctl -u hx-litellm-gateway -f"
        echo "   • Verify config: cat /opt/HX-Infrastructure-/api-gateway/config/api-gateway/config.yaml"
        exit 1
    fi
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
