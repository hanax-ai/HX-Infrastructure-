#!/usr/bin/env bash

echo "🧪 LLM-02 Model Test Suite"
echo "=========================="
echo

# Test each LLM-02 model individually
# Based on ollama list from LLM-02: cogito:32b, deepcoder:14b, dolphin3:8b, gemma2:2b, phi3:latest
models=("llm02-cogito-32b" "llm02-deepcoder-14b" "llm02-dolphin3-8b" "llm02-gemma2-2b" "llm02-phi3")
prompts=(
    "What is the meaning of life?"
    "Write a Python function to calculate fibonacci numbers"
    "Tell me a creative short story"
    "Explain quantum computing briefly"
    "What is artificial intelligence?"
)

echo "🔍 Checking LLM-02 connectivity..."
if curl -s --max-time 5 "http://192.168.10.28:11434/api/version" >/dev/null; then
    echo "✅ LLM-02 server reachable"
else
    echo "❌ LLM-02 server unreachable"
    exit 1
fi

echo
echo "📋 Available models on LLM-02 (direct):"
curl -s "http://192.168.10.28:11434/api/tags" | jq -r '.models[].name' | sort | sed 's/^/   • /'

echo
echo "📋 Available LLM-02 models in API Gateway:"
curl -s -H "Authorization: Bearer sk-hx-dev-1234" "http://localhost:4000/v1/models" | jq -r '.data[].id' | grep llm02 | sort | sed 's/^/   • /'

echo
echo "🧪 Testing each LLM-02 model:"
echo

for i in "${!models[@]}"; do
    model="${models[$i]}"
    prompt="${prompts[$i]}"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🤖 Testing: $model"
    echo "📝 Prompt: $prompt"
    echo
    
    # Check if model exists in gateway first
    if ! curl -s -H "Authorization: Bearer sk-hx-dev-1234" "http://localhost:4000/v1/models" | jq -e ".data[] | select(.id==\"$model\")" >/dev/null 2>&1; then
        echo "⚠️  SKIPPED: Model '$model' not configured in API Gateway"
        echo "💡 Add this model to config.yaml to test it"
        echo
        continue
    fi
    
    echo "⏳ Generating response (max 5 minutes for large models)..."
    
    # Set timeout based on model size - larger models need more time
    timeout=180  # 3 minutes default
    case "$model" in
        *cogito*) timeout=300 ;;      # 5 minutes for 32B model (19GB)
        *deepcoder*) timeout=300 ;;   # 5 minutes for 14B model (9GB)
        *dolphin3*) timeout=240 ;;    # 4 minutes for 8B model (4.9GB)
        *) timeout=120 ;;             # 2 minutes for smaller models
    esac
    
    echo "   Using ${timeout}s timeout for this model size..."
    
    response=$(curl -s --max-time $timeout -X POST "http://localhost:4000/v1/chat/completions" \
        -H "Authorization: Bearer sk-hx-dev-1234" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$model\",
            \"messages\": [{\"role\": \"user\", \"content\": \"$prompt\"}],
            \"temperature\": 0.3,
            \"max_tokens\": 150
        }" | jq -r '.choices[0].message.content // "ERROR: No response"' 2>/dev/null)
    
    if [[ "$response" != "ERROR: No response" && -n "$response" ]]; then
        echo "✅ SUCCESS"
        echo "📤 Response:"
        echo "   ${response:0:200}..."
        if [[ ${#response} -gt 200 ]]; then
            echo "   [Response truncated - full length: ${#response} characters]"
        fi
        echo
        
        # Get token usage info
        tokens=$(curl -s --max-time 10 -X POST "http://localhost:4000/v1/chat/completions" \
            -H "Authorization: Bearer sk-hx-dev-1234" \
            -H "Content-Type: application/json" \
            -d "{
                \"model\": \"$model\",
                \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}],
                \"temperature\": 0,
                \"max_tokens\": 5
            }" | jq -r '.usage.total_tokens // "N/A"' 2>/dev/null)
        echo "📊 Token Usage Test: $tokens tokens"
        
    else
        echo "❌ FAILED"
        echo "📤 Response: $response"
        
        # Try to get error details with appropriate timeout
        error=$(curl -s --max-time $timeout -X POST "http://localhost:4000/v1/chat/completions" \
            -H "Authorization: Bearer sk-hx-dev-1234" \
            -H "Content-Type: application/json" \
            -d "{
                \"model\": \"$model\",
                \"messages\": [{\"role\": \"user\", \"content\": \"$prompt\"}],
                \"temperature\": 0.3,
                \"max_tokens\": 150
            }" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
        echo "🔍 Error Details: $error"
    fi
    echo
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏁 LLM-02 Test Suite Complete"
echo
echo "💡 LLM-02 Model Specifications:"
echo "   • llm02-cogito-32b     - Large reasoning model (19GB) - Premium quality"
echo "   • llm02-deepcoder-14b  - Code-specialized model (9GB) - Programming tasks"
echo "   • llm02-dolphin3-8b    - Creative/conversational (4.9GB) - Chat optimized"
echo "   • llm02-gemma2-2b      - Compact efficient model (1.6GB) - Fast responses"
echo "   • llm02-phi3           - Microsoft research model (2.2GB) - Balanced"
echo
echo "🎯 Load Balancer Recommendations:"
echo "   • hx-chat-premium   → cogito:32b (best quality, slower)"
echo "   • hx-chat-code      → deepcoder:14b (code tasks)"
echo "   • hx-chat-creative  → dolphin3:8b (conversations)"
echo "   • hx-chat-fast      → gemma2:2b (quick responses)"
echo
echo "🔧 To add missing models, update /opt/HX-Infrastructure-/api-gateway/config/api-gateway/config.yaml"
