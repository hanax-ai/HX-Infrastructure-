#!/usr/bin/env bash

echo "🧪 HX-Infrastructure Smart Fleet Test Suite"
echo "============================================"
echo
echo "Testing ALL models with appropriate endpoints:"
echo "• Chat models → /v1/chat/completions"  
echo "• Embedding models → /v1/embeddings"
echo "Date: $(date)"
echo "Gateway: http://localhost:4000"
echo

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_test() { echo -e "${BLUE}[TEST]${NC} $1"; ((TOTAL_TESTS++)); }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASSED_TESTS++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAILED_TESTS++)); }
log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Test embedding models
test_embedding_model() {
    local model_name="$1"
    local description="$2"
    local server="$3"
    
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Testing EMBEDDING: $model_name ($description)"
    log_info "Server: $server"
    
    # Test 1: Model availability
    log_test "Model availability check"
    if curl -s -H "Authorization: Bearer sk-hx-dev-1234" "http://localhost:4000/v1/models" \
        | jq -e ".data[] | select(.id==\"$model_name\")" >/dev/null 2>&1; then
        log_pass "✓ Model '$model_name' available"
    else
        log_fail "✗ Model '$model_name' not available"
        return 1
    fi
    
    # Test 2: Single string embedding
    log_test "Single string embedding"
    response=$(curl -s --max-time 30 -X POST "http://localhost:4000/v1/embeddings" \
        -H "Authorization: Bearer sk-hx-dev-1234" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$model_name\", \"input\": \"test embedding\"}" \
        2>/dev/null)
    
    if echo "$response" | jq -e '.data[0].embedding | length' >/dev/null 2>&1; then
        dimensions=$(echo "$response" | jq -r '.data[0].embedding | length')
        log_pass "✓ Single embedding successful: $dimensions dimensions"
    else
        log_fail "✗ Single embedding failed"
        echo "Response: ${response:0:200}..."
        return 1
    fi
    
    # Test 3: Batch embeddings
    log_test "Batch embedding (3 inputs)"
    response=$(curl -s --max-time 30 -X POST "http://localhost:4000/v1/embeddings" \
        -H "Authorization: Bearer sk-hx-dev-1234" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$model_name\", \"input\": [\"first\", \"second\", \"third\"]}" \
        2>/dev/null)
    
    if echo "$response" | jq -e '.data | length' >/dev/null 2>&1; then
        count=$(echo "$response" | jq -r '.data | length')
        if [[ "$count" == "3" ]]; then
            log_pass "✓ Batch embedding successful: $count vectors"
        else
            log_fail "✗ Batch embedding returned $count vectors, expected 3"
        fi
    else
        log_fail "✗ Batch embedding failed"
        echo "Response: ${response:0:200}..."
        return 1
    fi
    
    # Test 4: Usage reporting
    log_test "Usage reporting"
    if echo "$response" | jq -e '.usage.total_tokens' >/dev/null 2>&1; then
        tokens=$(echo "$response" | jq -r '.usage.total_tokens')
        log_pass "✓ Usage reported: $tokens tokens"
    else
        log_warn "⚠ Usage reporting not available"
    fi
}

# Test chat models with dynamic timeouts
test_chat_model() {
    local model_name="$1"
    local description="$2"
    local server="$3"
    local prompt="$4"
    
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Testing CHAT: $model_name ($description)"
    log_info "Server: $server"
    log_info "Prompt: $prompt"
    
    # Set timeout based on model size
    timeout=120  # Default 2 minutes
    case "$model_name" in
        *cogito*) timeout=300 ;;        # 5 minutes for 32B model (19GB)
        *deepcoder*) timeout=300 ;;     # 5 minutes for 14B model (9GB)
        *mistral-small3.2*) timeout=300 ;; # 5 minutes for 24B model (15GB)
        *dolphin3*) timeout=240 ;;      # 4 minutes for 8B model (4.9GB)
        *) timeout=120 ;;               # 2 minutes for smaller models
    esac
    
    log_info "Using timeout: ${timeout}s"
    
    # Test 1: Model availability
    log_test "Model availability check"
    if curl -s -H "Authorization: Bearer sk-hx-dev-1234" "http://localhost:4000/v1/models" \
        | jq -e ".data[] | select(.id==\"$model_name\")" >/dev/null 2>&1; then
        log_pass "✓ Model '$model_name' available"
    else
        log_fail "✗ Model '$model_name' not available"
        return 1
    fi
    
    # Test 2: Chat completion
    log_test "Chat completion (timeout: ${timeout}s)"
    echo "⏳ Generating response..."
    response=$(curl -s --max-time "$timeout" -X POST "http://localhost:4000/v1/chat/completions" \
        -H "Authorization: Bearer sk-hx-dev-1234" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$model_name\",
            \"messages\": [{\"role\": \"user\", \"content\": \"$prompt\"}],
            \"temperature\": 0.3,
            \"max_tokens\": 100
        }" 2>/dev/null)
    
    if echo "$response" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
        content=$(echo "$response" | jq -r '.choices[0].message.content')
        log_pass "✓ Chat completion successful"
        echo "   Response: ${content:0:150}..."
        if [[ ${#content} -gt 150 ]]; then
            echo "   [Truncated - full length: ${#content} chars]"
        fi
    else
        log_fail "✗ Chat completion failed"
        error=$(echo "$response" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
        echo "   Error: $error"
        return 1
    fi
    
    # Test 3: Token usage
    log_test "Token usage reporting"
    if echo "$response" | jq -e '.usage.total_tokens' >/dev/null 2>&1; then
        tokens=$(echo "$response" | jq -r '.usage.total_tokens')
        log_pass "✓ Token usage: $tokens tokens"
    else
        log_fail "✗ Token usage not reported"
    fi
}

# Main test execution
main() {
    echo "=== PRE-FLIGHT CHECKS ==="
    
    # Check gateway
    log_test "API Gateway connectivity"
    if curl -s --max-time 10 "http://localhost:4000/v1/models" -H "Authorization: Bearer sk-hx-dev-1234" >/dev/null 2>&1; then
        log_pass "✓ API Gateway responding"
    else
        log_fail "✗ API Gateway not responding"
        exit 1
    fi
    
    # Check backend servers
    servers=("192.168.10.29:11434" "192.168.10.28:11434" "192.168.10.31:11434")
    names=("LLM-01" "LLM-02" "ORC")
    
    for i in "${!servers[@]}"; do
        server="${servers[$i]}"
        name="${names[$i]}"
        log_test "$name server connectivity"
        if curl -s --max-time 10 "http://$server/api/version" >/dev/null 2>&1; then
            log_pass "✓ $name reachable"
        else
            log_fail "✗ $name unreachable ($server)"
        fi
    done
    
    echo
    log_info "Available models in API Gateway:"
    curl -s -H "Authorization: Bearer sk-hx-dev-1234" "http://localhost:4000/v1/models" | jq -r '.data[].id' | sort | sed 's/^/   • /'
    
    echo
    echo "=== EMBEDDING MODEL TESTS ==="
    
    # Test embedding models (ORC server)
    test_embedding_model "emb-premium" "mxbai-embed-large (1024-dim)" "ORC"
    test_embedding_model "emb-perf" "nomic-embed-text" "ORC"  
    test_embedding_model "emb-light" "all-minilm" "ORC"
    
    echo
    echo "=== CHAT MODEL TESTS ==="
    echo
    echo "--- LLM-01 MODELS ---"
    
    # Test LLM-01 models
    test_chat_model "llm01-llama3.2-3b" "Meta Llama 3.2 3B (2GB)" "LLM-01" "What is 2+2?"
    test_chat_model "llm01-qwen3-1.7b" "Alibaba Qwen3 1.7B (1.4GB)" "LLM-01" "Hello, how are you?"
    test_chat_model "llm01-mistral-small3.2" "Mistral Small 3.2 24B (15GB)" "LLM-01" "Explain AI briefly."
    
    echo
    echo "--- LLM-02 MODELS ---"
    
    # Test LLM-02 models
    test_chat_model "llm02-cogito-32b" "Cogito 32B (19GB)" "LLM-02" "What is the meaning of life?"
    test_chat_model "llm02-deepcoder-14b" "DeepCoder 14B (9GB)" "LLM-02" "Write a Python function to calculate factorial"
    test_chat_model "llm02-dolphin3-8b" "Dolphin3 8B (4.9GB)" "LLM-02" "Tell me a short joke"
    test_chat_model "llm02-gemma2-2b" "Google Gemma2 2B (1.6GB)" "LLM-02" "Explain quantum computing briefly"
    test_chat_model "llm02-phi3" "Microsoft Phi3 (2.2GB)" "LLM-02" "What is machine learning?"
    
    echo
    echo "=== LOAD BALANCER TESTS ==="
    
    # Test load balancer models
    test_chat_model "hx-chat" "Default Balanced Chat" "Load Balancer" "Hello world"
    test_chat_model "hx-chat-fast" "Fast Responses" "Load Balancer" "Quick test"
    test_chat_model "hx-chat-code" "Code Specialized" "Load Balancer" "def hello():"
    test_chat_model "hx-chat-premium" "Premium Quality" "Load Balancer" "Explain consciousness"
    test_chat_model "hx-chat-creative" "Creative Chat" "Load Balancer" "Write a haiku about AI"
    
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🏁 HX-Infrastructure Fleet Test Complete"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "📊 FINAL RESULTS:"
    echo "   Total Tests: $TOTAL_TESTS"
    echo -e "   Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "   Failed: ${RED}$FAILED_TESTS${NC}"
    echo "   Success Rate: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
    echo
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}🎉 ALL SYSTEMS OPERATIONAL!${NC}"
        echo
        echo "✅ HX-Infrastructure API Gateway Status:"
        echo "   • Embedding Models: 3/3 operational (ORC server)"
        echo "   • LLM-01 Chat Models: 3/3 operational" 
        echo "   • LLM-02 Chat Models: 5/5 operational"
        echo "   • Load Balancer Models: 5/5 operational"
        echo
        echo "🚀 Total: 16 models operational across 3 servers!"
        exit 0
    else
        echo -e "${RED}⚠️  Some tests failed - review details above${NC}"
        echo
        echo "🔧 Troubleshooting:"
        echo "   • Check logs: sudo journalctl -u hx-litellm-gateway -f"
        echo "   • Verify backends: curl http://192.168.10.{29,28,31}:11434/api/version"
        echo "   • Test direct: ollama embed -m mxbai-embed-large 'test'"
        exit 1
    fi
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
