#!/usr/bin/env bash
set -euo pipefail

echo "🧪 Simple LLM-01 Model Test"
echo "============================"

# Test 1: Direct LLM-01 connectivity
echo "1. Testing LLM-01 connectivity..."
if curl -s --max-time 5 "http://192.168.10.29:11434/api/version" >/dev/null; then
    echo "✅ LLM-01 reachable"
else
    echo "❌ LLM-01 unreachable"
    exit 1
fi

# Test 2: Available models on LLM-01
echo "2. Available models on LLM-01:"
curl -s --max-time 5 "http://192.168.10.29:11434/api/tags" | jq -r '.models[].name' | sort

# Test 3: API Gateway models
echo "3. Available models in API Gateway:"
curl -s --max-time 5 -H "Authorization: Bearer sk-hx-dev-1234" "http://localhost:4000/v1/models" | jq -r '.data[].id' | sort

# Test 4: Test existing llm01-llama3.2-3b model
echo "4. Testing llm01-llama3.2-3b via API Gateway..."
RESPONSE=$(curl -s --max-time 15 -X POST "http://localhost:4000/v1/chat/completions" \
  -H "Authorization: Bearer sk-hx-dev-1234" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llm01-llama3.2-3b",
    "messages": [{"role": "user", "content": "Say: TEST-OK"}],
    "temperature": 0,
    "max_tokens": 10
  }' | jq -r '.choices[0].message.content // "ERROR"')

echo "Response: $RESPONSE"

if [[ "$RESPONSE" =~ "TEST-OK" ]]; then
    echo "✅ llm01-llama3.2-3b working correctly"
else
    echo "❌ llm01-llama3.2-3b test failed"
fi

echo "✅ Simple test completed"
