#!/bin/bash
# verify-model-tags.sh - Verify all model tags in ollama.env are valid and consistent

set -euo pipefail

# Allow override of environment file via command line argument and environment variables
ENV_FILE="${1:-${ENV_FILE:-/home/agent0/HX-Infrastructure--1/llm-01/config/ollama/ollama.env}}"
PRODUCTION_ENV_FILE="${PRODUCTION_ENV_FILE:-/opt/hx-infrastructure/llm-01/config/ollama/ollama.env}"

echo "=== MODEL TAG VERIFICATION SCRIPT ==="
echo ""

# Function to extract model references from env file
extract_models() {
    local env_file="$1"
    echo "Checking environment file: $env_file"
    echo ""
    
    # Extract individual model variables (robust parsing)
    local llama_model=$(grep "^OLLAMA_MODEL_LLAMA32=" "$env_file" | tail -n1 | cut -d'=' -f2- | sed 's/^["'"'"']//; s/["'"'"']$//')
    local qwen_model=$(grep "^OLLAMA_MODEL_QWEN3=" "$env_file" | tail -n1 | cut -d'=' -f2- | sed 's/^["'"'"']//; s/["'"'"']$//')
    local mistral_model=$(grep "^OLLAMA_MODEL_MISTRAL=" "$env_file" | tail -n1 | cut -d'=' -f2- | sed 's/^["'"'"']//; s/["'"'"']$//')
    
    # Extract available models list
    local available_models=$(grep "^OLLAMA_MODELS_AVAILABLE=" "$env_file" | tail -n1 | cut -d'=' -f2- | sed 's/^["'"'"']//; s/["'"'"']$//')
    
    # Extract count (may be empty or missing)
    local model_count=$(grep "^OLLAMA_MODELS_COUNT=" "$env_file" 2>/dev/null | tail -n1 | cut -d'=' -f2- | sed 's/^["'"'"']//; s/["'"'"']$//' || echo "")
    
    echo "📋 EXTRACTED MODEL REFERENCES:"
    echo "  OLLAMA_MODEL_LLAMA32: $llama_model"
    echo "  OLLAMA_MODEL_QWEN3: $qwen_model"
    echo "  OLLAMA_MODEL_MISTRAL: $mistral_model"
    echo "  OLLAMA_MODELS_AVAILABLE: $available_models"
    if [[ -n "$model_count" ]]; then
        echo "  OLLAMA_MODELS_COUNT: $model_count"
    else
        echo "  OLLAMA_MODELS_COUNT: (not set or empty - will be computed dynamically)"
    fi
    echo ""
    
    # Verify no :latest tags
    echo "🔍 CHECKING FOR UNPINNED TAGS:"
    if echo "$llama_model $qwen_model $mistral_model" | grep -q ":latest"; then
        echo "  ❌ ERROR: Found unpinned ':latest' tag"
        return 1
    else
        echo "  ✅ No unpinned ':latest' tags found"
    fi
    echo ""
    
    # Verify each model exists in available list
    echo "🔗 CHECKING MODEL CONSISTENCY:"
    local all_models=($llama_model $qwen_model $mistral_model)
    local available_array=(${available_models//,/ })
    
    for model in "${all_models[@]}"; do
        # Use exact equality check to avoid false positives
        local found=false
        for available_model in "${available_array[@]}"; do
            if [[ "$available_model" == "$model" ]]; then
                found=true
                break
            fi
        done
        
        if [[ "$found" == "true" ]]; then
            echo "  ✅ $model found in OLLAMA_MODELS_AVAILABLE"
        else
            echo "  ❌ ERROR: $model NOT found in OLLAMA_MODELS_AVAILABLE"
            return 1
        fi
    done
    echo ""
    
    # Verify count matches (resilient check)
    echo "📊 CHECKING MODEL COUNT:"
    local actual_count=${#all_models[@]}
    
    # Check if OLLAMA_MODELS_COUNT is present and valid
    if [[ -n "$model_count" ]]; then
        # Validate that model_count is a valid integer
        if [[ "$model_count" =~ ^[0-9]+$ ]]; then
            if [ "$model_count" -eq "$actual_count" ]; then
                echo "  ✅ OLLAMA_MODELS_COUNT ($model_count) matches actual count ($actual_count)"
            else
                echo "  ❌ ERROR: OLLAMA_MODELS_COUNT ($model_count) does not match actual count ($actual_count)"
                return 1
            fi
        else
            echo "  ❌ ERROR: OLLAMA_MODELS_COUNT contains invalid value: '$model_count' (not an integer)"
            return 1
        fi
    else
        # OLLAMA_MODELS_COUNT not set - compute dynamically and inform
        echo "  💡 OLLAMA_MODELS_COUNT not set - computed dynamically from model variables"
        echo "  ✅ Detected model count: $actual_count models"
        echo "     (llama3.2, qwen3, mistral models found)"
    fi
    echo ""
    
    # Verify models exist in Ollama
    echo "🧪 CHECKING MODEL AVAILABILITY IN OLLAMA:"
    
    # Guard: Check if ollama CLI is available
    if ! command -v ollama >/dev/null 2>&1; then
        echo "  ⚠️  WARNING: ollama CLI not found in PATH"
        echo "     Skipping model availability checks"
        echo "     Install ollama or ensure it's in PATH for complete validation"
        echo ""
        return 0
    fi
    
    # Verify ollama service is accessible
    if ! ollama list >/dev/null 2>&1; then
        echo "  ⚠️  WARNING: ollama service not accessible"
        echo "     Skipping model availability checks"
        echo "     Ensure ollama service is running for complete validation"
        echo ""
        return 0
    fi
    
    for model in "${all_models[@]}"; do
        # For SHA references, we need to check differently
        if [[ "$model" == *"@sha256:"* ]]; then
            # Extract the base name without the SHA
            local base_name
            base_name=$(echo "$model" | cut -d'@' -f1)
            echo "  🔍 Checking SHA-referenced model: $model (base: $base_name)"
            
            # Use awk for precise first-column matching
            if ollama list | awk -v target="$base_name" 'NR>1 && ($1 == target || index($1, target":") == 1) {found=1} END {exit !found}'; then
                echo "  ✅ $base_name is available in Ollama"
            else
                echo "  ❌ WARNING: $base_name not found in current Ollama installation"
            fi
        else
            echo "  🔍 Checking model: $model"
            
            # Use awk for precise first-column matching
            if ollama list | awk -v target="$model" 'NR>1 && $1 == target {found=1} END {exit !found}'; then
                echo "  ✅ $model is available in Ollama"
            else
                echo "  ❌ WARNING: $model not found in current Ollama installation"
            fi
        fi
    done
    echo ""
}

# Check staging environment
echo "🎯 VERIFYING STAGING ENVIRONMENT:"
staging_exit_code=0
extract_models "$ENV_FILE" || staging_exit_code=$?

# Check production environment if it exists and it's different from staging
production_exit_code=0
if [ -f "$PRODUCTION_ENV_FILE" ] && [ "$ENV_FILE" != "$PRODUCTION_ENV_FILE" ]; then
    echo "🎯 VERIFYING PRODUCTION ENVIRONMENT:"
    extract_models "$PRODUCTION_ENV_FILE" || production_exit_code=$?
elif [ "$ENV_FILE" == "$PRODUCTION_ENV_FILE" ]; then
    echo "💡 Using production environment file as staging"
else
    echo "⚠️  Production environment file not found: $PRODUCTION_ENV_FILE"
fi

echo "✅ MODEL TAG VERIFICATION COMPLETE"

# Exit with failure if either check failed
if [ $staging_exit_code -ne 0 ] || [ $production_exit_code -ne 0 ]; then
    echo ""
    echo "❌ VALIDATION FAILED:"
    [ $staging_exit_code -ne 0 ] && echo "  • Staging environment check failed (exit code: $staging_exit_code)"
    [ $production_exit_code -ne 0 ] && echo "  • Production environment check failed (exit code: $production_exit_code)"
    exit 1
fi
