#!/usr/bin/env bash

echo "🧪 LLM-01 Model Test Suite"
echo "========================="
echo

# Test each LLM-01 model individually
models=("llm01-llama3.2-3b" "llm01-qwen3-1.7b" "llm01-mistral-small3.2")
prompts=("What is 2+2?" "Hello!" "Explain AI briefly.")

echo "Available models:"
curl -s -H "Authorization: Bearer sk-hx-dev-1234" "http://localhost:4000/v1/models" | jq -r '.data[].id' | grep llm01 | sort

echo
echo "Testing each LLM-01 model:"
echo

for i in "${!models[@]}"; do
    model="${models[$i]}"
    prompt="${prompts[$i]}"
    
    echo "----------------------------------------"
    echo "🤖 Testing: $model"
    echo "📝 Prompt: $prompt"
    echo
    
    response=$(curl -s --max-time 20 -X POST "http://localhost:4000/v1/chat/completions" \
        -H "Authorization: Bearer sk-hx-dev-1234" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$model\",
            \"messages\": [{\"role\": \"user\", \"content\": \"$prompt\"}],
            \"temperature\": 0.3,
            \"max_tokens\": 100
        }" | jq -r '.choices[0].message.content // "ERROR: No response"' 2>/dev/null)
    
    if [[ "$response" != "ERROR: No response" && -n "$response" ]]; then
        echo "✅ SUCCESS"
        echo "📤 Response: $response"
        echo
    else
        echo "❌ FAILED"
        echo "📤 Response: $response"
        echo
        # Try to get error details
        error=$(curl -s --max-time 20 -X POST "http://localhost:4000/v1/chat/completions" \
            -H "Authorization: Bearer sk-hx-dev-1234" \
            -H "Content-Type: application/json" \
            -d "{
                \"model\": \"$model\",
                \"messages\": [{\"role\": \"user\", \"content\": \"$prompt\"}],
                \"temperature\": 0.3,
                \"max_tokens\": 100
            }" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
        echo "🔍 Error: $error"
        echo
    fi
done

echo "========================================="
echo "🏁 Test completed"
echo
echo "💡 Available LLM-01 models via API Gateway:"
echo "   • llm01-llama3.2-3b      - Meta Llama 3.2 3B (2GB)"
echo "   • llm01-qwen3-1.7b       - Alibaba Qwen3 1.7B (1.4GB)" 
echo "   • llm01-mistral-small3.2 - Mistral Small 3.2 24B (15GB)"
