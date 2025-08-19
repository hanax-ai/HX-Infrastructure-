#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - Orchestrate ALL model inference tests across both LLM instances
# This script follows the Open/Closed principle - easy to add new test suites without modification

echo "🌟 Complete Fleet Inference Test Suite"
echo "======================================"
echo "Testing all models across LLM-01 and LLM-02 via API Gateway"
echo

# Configuration - Environment variables with fallbacks (SOLID: Dependency Inversion)
export API_BASE="${API_BASE:-http://localhost:4000}"

# Validate required environment variables
if [[ -z "${MASTER_KEY:-}" ]]; then
    echo "ERROR: MASTER_KEY environment variable is required" >&2
    echo "Please set MASTER_KEY before running this script" >&2
    exit 1
fi

export MASTER_KEY
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test suite definitions (SOLID: Open/Closed - easy to extend)
declare -A test_suites=(
    ["llm01"]="LLM-01 Instance - Mistral, Qwen3, Llama3 models"
    ["llm02"]="LLM-02 Instance - Cogito, DeepCoder, Dolphin3, Gemma2, Phi3 models"
)

# Model count mapping to avoid duplication and drift
declare -A suite_model_counts=(
    ["llm01"]=3
    ["llm02"]=5
)

# Test results tracking
declare -A suite_results
total_suites=${#test_suites[@]}
passed_suites=0
total_models=0
total_passed_models=0

echo "Discovered $total_suites test suites to run"
echo

# Execute each test suite (SOLID: Single Responsibility per suite)
for suite in "${!test_suites[@]}"; do
    description="${test_suites[$suite]}"
    # Try suites/ directory first, fallback to script directory
    if [[ -f "${SCRIPT_DIR}/suites/${suite}_inference_suite.sh" ]]; then
        suite_script="${SCRIPT_DIR}/suites/${suite}_inference_suite.sh"
    else
        suite_script="${SCRIPT_DIR}/${suite}_inference_suite.sh"
    fi
    
    echo "Running Suite: $suite"
    echo "Description: $description"
    echo "Script: $suite_script"
    
    if [[ -f "$suite_script" ]]; then
        echo "Executing test suite..."
        
        # Make executable and run suite
        chmod +x "$suite_script"
        
        if timeout 600 "$suite_script"; then
            suite_results["$suite"]="PASS"
            echo "✅ $suite: ALL MODELS PASSED"
            ((passed_suites++))
            
            # Count models in this suite using associative map
            model_count=${suite_model_counts[$suite]:-0}
            total_models=$((total_models + model_count))
            total_passed_models=$((total_passed_models + model_count))
        else
            suite_results["$suite"]="FAIL"
            echo "❌ $suite: SOME MODELS FAILED"
            
            # Count models in this suite using associative map
            model_count=${suite_model_counts[$suite]:-0}
            total_models=$((total_models + model_count))
        fi
    else
        suite_results["$suite"]="MISSING"
        echo "⚠️  $suite: Test suite script not found"
    fi
    
    echo "============================================"
done

# Final results summary
echo
echo "🏆 Complete Fleet Test Results"
echo "=============================="
echo "Test Suites: $total_suites"
echo "Suites Passed: $passed_suites"
echo "Total Models: $total_models"
echo "Models Passed: $total_passed_models"
echo

echo "Suite Results:"
for suite in "${!test_suites[@]}"; do
    status="${suite_results[$suite]:-UNKNOWN}"
    case "$status" in
        "PASS") echo "✅ $suite: ALL MODELS SUCCESS" ;;
        "FAIL") echo "❌ $suite: SOME MODELS FAILED" ;;
        "MISSING") echo "⚠️  $suite: NO TEST SUITE" ;;
        *) echo "❓ $suite: UNKNOWN STATUS" ;;
    esac
done

echo
if [[ $passed_suites -eq $total_suites ]]; then
    echo "🎉 COMPLETE SUCCESS: All models across all instances passed inference testing!"
    echo "Infrastructure Status: FULLY OPERATIONAL"
    echo "Models Validated: $total_passed_models/$total_models"
    exit 0
else
    echo "⚠️  PARTIAL SUCCESS: Some test suites had failures"
    echo "Infrastructure Status: NEEDS ATTENTION"
    exit 1
fi
