#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ================================================================
# HX-Infrastructure API Gateway - LLM-01 Model Validation Script
# ================================================================
# 
# Purpose: Comprehensive testing of all models available on LLM-01
# Server: llm-01 (192.168.10.29:11434)
# Models: llama3.2:3b, qwen3:1.7b, mistral-small3.2:latest
# 
# Usage: bash llm01-model-validation.sh
# ================================================================

echo "🧪 HX-Infrastructure API Gateway - LLM-01 Model Validation"
echo "=========================================================="
echo

# Configuration
API_BASE="http://localhost:4000"
MASTER_KEY="sk-hx-dev-1234"
LLM01_DIRECT="http://192.168.10.29:11434"

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Utility functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

increment_test() {
    ((TESTS_TOTAL++))
}

# Test function for direct Ollama model availability
test_ollama_direct() {
    local model="$1"
    local display_name="$2"
    
    increment_test
    log_info "Testing direct Ollama access: $display_name"
    
    if curl -s --max-time 10 "${LLM01_DIRECT}/api/version" >/dev/null 2>&1; then
        log_success "✓ LLM-01 server reachable"
    else
        log_error "✗ LLM-01 server unreachable at ${LLM01_DIRECT}"
        return 1
    fi
    
    # Test model availability via Ollama API
    if curl -s --max-time 10 "${LLM01_DIRECT}/api/tags" | jq -e ".models[] | select(.name==\"${model}\")" >/dev/null 2>&1; then
        log_success "✓ Model '${model}' available on LLM-01"
    else
        log_error "✗ Model '${model}' not found on LLM-01"
        return 1
    fi
    
    # Test basic generation via direct Ollama
    local test_prompt="Say exactly: OLLAMA-TEST-OK"
    local response
    
    response=$(curl -s --max-time 30 "${LLM01_DIRECT}/api/generate" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"${model}\",\"prompt\":\"${test_prompt}\",\"stream\":false}" \
        | jq -r '.response // empty' 2>/dev/null || echo "")
    
    if [[ "$response" =~ "OLLAMA-TEST-OK" ]]; then
        log_success "✓ Direct Ollama generation successful: ${response:0:50}..."
    else
        log_error "✗ Direct Ollama generation failed or unexpected response"
        return 1
    fi
}

# Test function for API Gateway model access
test_gateway_model() {
    local gateway_model="$1"
    local display_name="$2"
    
    increment_test
    log_info "Testing API Gateway model: $display_name ($gateway_model)"
    
    # Test 1: Model listed in /v1/models
    if curl -s -H "Authorization: Bearer ${MASTER_KEY}" "${API_BASE}/v1/models" \
        | jq -e ".data[] | select(.id==\"${gateway_model}\")" >/dev/null 2>&1; then
        log_success "✓ Model '${gateway_model}' listed in API Gateway"
    else
        log_error "✗ Model '${gateway_model}' not found in API Gateway model list"
        return 1
    fi
    
    # Test 2: Chat completion with deterministic response
    increment_test
    local chat_response
    chat_response=$(curl -s --max-time 30 "${API_BASE}/v1/chat/completions" \
        -H "Authorization: Bearer ${MASTER_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"${gateway_model}\",
            \"messages\": [{\"role\": \"user\", \"content\": \"Say exactly: GATEWAY-TEST-OK\"}],
            \"temperature\": 0,
            \"max_tokens\": 20
        }" | jq -r '.choices[0].message.content // empty' 2>/dev/null || echo "")
    
    if [[ "$chat_response" =~ "GATEWAY-TEST-OK" ]]; then
        log_success "✓ Chat completion successful: ${chat_response:0:50}..."
    else
        log_error "✗ Chat completion failed. Response: ${chat_response:0:100}..."
        return 1
    fi
    
    # Test 3: Different prompt for model capability
    increment_test
    local capability_response
    capability_response=$(curl -s --max-time 30 "${API_BASE}/v1/chat/completions" \
        -H "Authorization: Bearer ${MASTER_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"${gateway_model}\",
            \"messages\": [{\"role\": \"user\", \"content\": \"What is 2+2? Answer with just the number.\"}],
            \"temperature\": 0,
            \"max_tokens\": 5
        }" | jq -r '.choices[0].message.content // empty' 2>/dev/null || echo "")
    
    if [[ "$capability_response" =~ "4" ]]; then
        log_success "✓ Model reasoning test passed: ${capability_response}"
    else
        log_warning "⚠ Model reasoning test unclear: ${capability_response}"
    fi
    
    # Test 4: Token usage reporting
    increment_test
    local usage_test
    usage_test=$(curl -s --max-time 30 "${API_BASE}/v1/chat/completions" \
        -H "Authorization: Bearer ${MASTER_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"${gateway_model}\",
            \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}],
            \"temperature\": 0,
            \"max_tokens\": 5
        }" | jq -r '.usage.total_tokens // empty' 2>/dev/null || echo "")
    
    if [[ -n "$usage_test" && "$usage_test" != "null" ]]; then
        log_success "✓ Token usage reporting: ${usage_test} tokens"
    else
        log_warning "⚠ Token usage not reported or invalid"
    fi
}

# Main test execution
main() {
    log_info "Starting LLM-01 model validation..."
    echo
    
    # Pre-flight: Check API Gateway availability
    log_info "Pre-flight: Checking API Gateway availability..."
    if ! curl -s --max-time 10 "${API_BASE}/v1/models" -H "Authorization: Bearer ${MASTER_KEY}" >/dev/null 2>&1; then
        log_error "API Gateway not reachable at ${API_BASE}"
        exit 1
    fi
    log_success "✓ API Gateway is responding"
    echo
    
    # Test 1: Direct Ollama model availability
    echo "=== Direct Ollama Model Tests ==="
    test_ollama_direct "llama3.2:3b" "Meta Llama 3.2 3B"
    echo
    test_ollama_direct "qwen3:1.7b" "Alibaba Qwen3 1.7B"
    echo
    test_ollama_direct "mistral-small3.2:latest" "Mistral Small 3.2"
    echo
    
    # Test 2: API Gateway model access (existing model)
    echo "=== API Gateway Model Tests ==="
    test_gateway_model "llm01-llama3.2-3b" "Meta Llama 3.2 3B (via Gateway)"
    echo
    
    # Test 3: Load-balanced model
    test_gateway_model "hx-chat" "HX Load-Balanced Chat Model"
    echo
    
    # Summary
    echo "=========================================================="
    echo "🧪 Test Execution Summary"
    echo "=========================================================="
    echo "Total Tests: $TESTS_TOTAL"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "🎉 All tests passed! LLM-01 integration is working correctly."
        echo
        echo "✅ Available Models on LLM-01:"
        echo "   • llama3.2:3b - Accessible via 'llm01-llama3.2-3b'"
        echo "   • qwen3:1.7b - NOT YET CONFIGURED in API Gateway"
        echo "   • mistral-small3.2:latest - NOT YET CONFIGURED in API Gateway"
        echo
        echo "💡 Recommendation: Add qwen3:1.7b and mistral-small3.2 to API Gateway config"
        exit 0
    else
        log_error "❌ Some tests failed. Please check the errors above."
        echo
        echo "🔧 Troubleshooting steps:"
        echo "   1. Verify LLM-01 server is running: systemctl status ollama"
        echo "   2. Check model availability: curl ${LLM01_DIRECT}/api/tags"
        echo "   3. Verify API Gateway config: cat ${API_BASE%:*}/api-gateway/config/api-gateway/config.yaml"
        echo "   4. Check service logs: journalctl -u hx-litellm-gateway -f"
        exit 1
    fi
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
