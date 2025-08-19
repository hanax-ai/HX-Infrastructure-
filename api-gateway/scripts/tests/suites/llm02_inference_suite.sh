#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - Orchestrate ONLY LLM-02 model inference tests
# This script follows the Open/Closed principle - easy to add new models without modification
#
# Environment Variables:
# - API_BASE: Gateway URL (default: http://localhost:4000)
# - MASTER_KEY: Authentication key (default: sk-hx-dev-1234)  
# - LLM_TEST_TIMEOUT: Test timeout in seconds (default: 300)

echo "🚀 LLM-02 Inference Test Suite"
echo "=============================="
echo "Testing all LLM-02 models via API Gateway"
echo

# Configuration - Environment variables with fallbacks (SOLID: Dependency Inversion)
API_BASE="${API_BASE:-http://localhost:4000}"
# Security: MASTER_KEY must be set externally
if [[ -z "${MASTER_KEY:-}" ]]; then
    echo "❌ ERROR: MASTER_KEY environment variable is required" >&2
    echo "   Please export MASTER_KEY=your-secure-key before running this script" >&2
    exit 1
fi

# Test timeout configuration (configurable via LLM_TEST_TIMEOUT env var, default: 300 seconds)
LLM_TEST_TIMEOUT="${LLM_TEST_TIMEOUT:-300}"
# Validate and coerce to integer
if ! [[ "$LLM_TEST_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$LLM_TEST_TIMEOUT" -lt 1 ]]; then
    echo "Warning: Invalid LLM_TEST_TIMEOUT value '$LLM_TEST_TIMEOUT', using default 300 seconds" >&2
    LLM_TEST_TIMEOUT=300
fi

# Export variables so child test scripts inherit the values
export API_BASE
export MASTER_KEY
export LLM_TEST_TIMEOUT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# LLM-02 model test definitions (SOLID: Open/Closed - easy to extend)
declare -A llm02_models=(
    ["cogito"]="Cogito 32B - Advanced reasoning and analysis"
    ["deepcoder"]="DeepCoder 14B - Code generation and debugging"
    ["dolphin3"]="Dolphin3 8B - General purpose conversational AI"
    ["gemma2"]="Gemma2 2B - Efficient text understanding and generation"
    ["phi3"]="Phi3 14B - Mathematical and logical reasoning"
)

# Test results tracking
declare -A test_results
total_models=${#llm02_models[@]}
passed_models=0

echo "Discovered $total_models LLM-02 models to test"
echo

# Execute each model's inference test (SOLID: Single Responsibility per model)
for model in "${!llm02_models[@]}"; do
    description="${llm02_models[$model]}"
    test_script="${SCRIPT_DIR}/../models/${model}/inference_test.sh"
    
    echo "Testing: $model ($description)"
    echo "Script: $test_script"
    
    if [[ -f "$test_script" ]]; then
        echo "Executing inference test (timeout: ${LLM_TEST_TIMEOUT}s)..."
        
        # Make executable and run test
        chmod +x "$test_script"
        
        if timeout "$LLM_TEST_TIMEOUT" "$test_script"; then
            test_results["$model"]="PASS"
            echo "✅ $model: PASSED"
            ((passed_models++))
        else
            test_results["$model"]="FAIL"
            echo "❌ $model: FAILED"
        fi
    else
        test_results["$model"]="MISSING"
        echo "⚠️  $model: Test script not found"
    fi
    
    echo "----------------------------------------"
done

# Final results summary
echo
echo "🏁 LLM-02 Test Suite Results"
echo "============================"
echo "Total Models: $total_models"
echo "Passed: $passed_models"
echo "Failed: $((total_models - passed_models))"
echo

echo "Detailed Results:"
for model in "${!llm02_models[@]}"; do
    status="${test_results[$model]:-UNKNOWN}"
    case "$status" in
        "PASS") echo "✅ $model: SUCCESS" ;;
        "FAIL") echo "❌ $model: FAILED" ;;
        "MISSING") echo "⚠️  $model: NO TEST" ;;
        *) echo "❓ $model: UNKNOWN" ;;
    esac
done

echo
if [[ $passed_models -eq $total_models ]]; then
    echo "🎉 SUCCESS: All LLM-02 models passed inference testing!"
    exit 0
else
    echo "⚠️  WARNING: Some LLM-02 models failed testing"
    exit 1
fi
