#!/bin/bash
# validate-model-config.sh - Pre-deploy validation for model configuration
# Computes model count and validates consistency from source of truth

set -euo pipefail

# Source shared model configuration library with robust path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Search for model-config.sh in likely locations
MODEL_CONFIG_PATHS=(
    "$SCRIPT_DIR/../lib/model-config.sh"
    "$SCRIPT_DIR/lib/model-config.sh"
    "$SCRIPT_DIR/../scripts/lib/model-config.sh"
)

MODEL_CONFIG_LIB=""
for path in "${MODEL_CONFIG_PATHS[@]}"; do
    if [[ -r "$path" ]]; then
        MODEL_CONFIG_LIB="$path"
        break
    fi
done

# Validate library file was found
if [[ -z "$MODEL_CONFIG_LIB" ]]; then
    echo "❌ ERROR: model-config.sh library not found in any expected location:" >&2
    for path in "${MODEL_CONFIG_PATHS[@]}"; do
        echo "   - $path" >&2
    done
    exit 1
fi

# Source the library
# shellcheck disable=SC1090
source "$MODEL_CONFIG_LIB"

# Verify required function is available
if ! declare -F extract_model_references >/dev/null 2>&1; then
    echo "❌ ERROR: Required function 'extract_model_references' not found in $MODEL_CONFIG_LIB" >&2
    echo "   The library may be corrupted or incompatible with this script" >&2
    exit 1
fi

ENV_FILE="${1:-/opt/hx-infrastructure/llm-01/config/ollama/ollama.env}"
VALIDATION_MODE="${2:-strict}"  # strict|info

# Validate VALIDATION_MODE parameter
VALIDATION_MODE=$(echo "$VALIDATION_MODE" | tr '[:upper:]' '[:lower:]')
if [[ "$VALIDATION_MODE" != "strict" && "$VALIDATION_MODE" != "info" ]]; then
    echo "❌ ERROR: Invalid validation mode '$2'" >&2
    echo "   Allowed values: strict, info" >&2
    echo "   Usage: $0 [env_file] [validation_mode]" >&2
    exit 1
fi

echo "=== PRE-DEPLOY MODEL CONFIGURATION VALIDATION ==="
echo "Environment file: $ENV_FILE"
echo "Validation mode: $VALIDATION_MODE"
echo ""

# Function to compute model count from per-model variables
compute_model_count_from_vars() {
    local env_file="$1"
    local count=0
    
    # Count OLLAMA_MODEL_* variables (excluding OLLAMA_MODELS_AVAILABLE)
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?OLLAMA_MODEL_[A-Za-z0-9_]+[[:space:]]*=[[:space:]]* ]] && [[ ! "$line" =~ OLLAMA_MODELS_ ]]; then
            ((count++))
        fi
    done < "$env_file"
    
    echo "$count"
}

# Function to compute model count from OLLAMA_MODELS_AVAILABLE
compute_model_count_from_available() {
    local env_file="$1"
    
    # Find the last non-commented line that starts with OLLAMA_MODELS_AVAILABLE
    # Allow optional whitespace around the = sign
    local available_value
    available_value=$(grep "^[[:space:]]*OLLAMA_MODELS_AVAILABLE[[:space:]]*=" "$env_file" | tail -n1 | sed 's/^[[:space:]]*OLLAMA_MODELS_AVAILABLE[[:space:]]*=[[:space:]]*//' | sed 's/[[:space:]]*$//')
    
    # Handle missing or empty value
    if [[ -z "$available_value" ]]; then
        echo "0"
        return
    fi
    
    # Strip surrounding quotes (single or double)
    available_value=$(echo "$available_value" | sed 's/^["'"'"']//' | sed 's/["'"'"']$//')
    
    # Treat empty or whitespace-only as zero
    if [[ -z "$available_value" || "$available_value" =~ ^[[:space:]]*$ ]]; then
        echo "0"
        return
    fi
    
    # Split on commas and count models using robust trimming and filtering
    local models_array
    local filtered_array=()
    IFS=',' read -ra models_array <<< "$available_value"
    
    # Iterate over array, trim whitespace, and keep only non-empty elements
    local element
    for element in "${models_array[@]}"; do
        # Trim leading and trailing whitespace
        element="${element#"${element%%[![:space:]]*}"}"  # Remove leading whitespace
        element="${element%"${element##*[![:space:]]}"}"  # Remove trailing whitespace
        
        # Append only non-empty trimmed values
        if [[ -n "$element" ]]; then
            filtered_array+=("$element")
        fi
    done
    
    echo "${#filtered_array[@]}"
}

# Function to verify per-model inclusion against OLLAMA_MODELS_AVAILABLE
verify_model_inclusion() {
    local env_file="$1"
    echo "🔗 MODEL INCLUSION VERIFICATION:"
    
    # Parse OLLAMA_MODELS_AVAILABLE into array
    local available_models
    available_models=$(grep "^[[:space:]]*OLLAMA_MODELS_AVAILABLE[[:space:]]*=" "$env_file" 2>/dev/null | tail -n1 | sed 's/^[^=]*=[[:space:]]*//' | sed 's/[[:space:]]*$//' || echo "")
    
    # Strip surrounding quotes if present
    available_models=$(echo "$available_models" | sed 's/^["'"'"']//' | sed 's/["'"'"']$//')
    
    if [[ -z "$available_models" || "$available_models" =~ ^[[:space:]]*$ ]]; then
        echo "  ❌ OLLAMA_MODELS_AVAILABLE is empty or not found"
        if [[ "$VALIDATION_MODE" == "strict" ]]; then
            echo ""
            echo "🚫 DEPLOYMENT BLOCKED: No available models list found"
            exit 1
        fi
        return
    fi
    
    # Convert comma-separated list to array for exact matching
    local IFS=','
    local available_array=($available_models)
    
    # Trim whitespace from each element
    local i
    for i in "${!available_array[@]}"; do
        available_array[$i]=$(echo "${available_array[$i]}" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    done
    
    echo "  Available models: ${available_array[*]}"
    
    # Check each OLLAMA_MODEL_* variable against available list
    local inclusion_errors=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*OLLAMA_MODEL_[A-Za-z0-9_]+[[:space:]]*= ]] && [[ ! "$line" =~ ^[[:space:]]*OLLAMA_MODELS_ ]]; then
            local var_name
            var_name=$(echo "$line" | sed 's/^[[:space:]]*\([^=]*\)[[:space:]]*=.*/\1/')
            
            # Extract model value
            local model_value
            model_value=$(echo "$line" | sed 's/^[^=]*=[[:space:]]*//')
            
            # Detect if value is quoted and handle comments appropriately
            if [[ "$model_value" =~ ^[[:space:]]*[\"\'] ]]; then
                # Value is quoted - strip only surrounding quotes, preserve # inside quotes
                model_value=$(echo "$model_value" | sed 's/^[[:space:]]*["'"'"']//' | sed 's/["'"'"'][[:space:]]*#.*$//' | sed 's/["'"'"'][[:space:]]*$//')
            else
                # Value is unquoted - remove trailing comments and trim whitespace
                model_value=$(echo "$model_value" | sed 's/[[:space:]]*#.*$//' | sed 's/[[:space:]]*$//')
            fi
            
            # Check exact membership in available models
            local found=false
            local available_model
            for available_model in "${available_array[@]}"; do
                if [[ "$model_value" == "$available_model" ]]; then
                    found=true
                    break
                fi
            done
            
            if [[ "$found" == "true" ]]; then
                echo "  ✅ $var_name ($model_value) found in available models"
            else
                echo "  ❌ $var_name ($model_value) NOT found in available models"
                inclusion_errors=true
            fi
        fi
    done < "$env_file"
    
    if [[ "$inclusion_errors" == "true" ]]; then
        echo "  ❌ ERROR: Model inclusion inconsistencies detected!"
        if [[ "$VALIDATION_MODE" == "strict" ]]; then
            echo ""
            echo "🚫 DEPLOYMENT BLOCKED: Models not in available list"
            exit 1
        fi
    else
        echo "  ✅ All individual models found in available models list"
    fi
    echo ""
}

# Function to compute total size from Ollama
compute_total_size() {
    echo "📊 COMPUTING TOTAL SIZE FROM OLLAMA:"
    
    # Extract model names and list sizes
    local models_found=0
    local total_display=""
    
    # Cache list output once with locale stability
    local _ollama_list
    _ollama_list="$(LC_ALL=C ollama list 2>/dev/null || true)"
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*OLLAMA_MODEL_[A-Za-z0-9_]+[[:space:]]*= ]] && [[ ! "$line" =~ ^[[:space:]]*OLLAMA_MODELS_ ]]; then
            # Extract RHS value (supports quoted/unquoted; trims whitespace and inline comments)
            local model_ref
            model_ref=$(echo "$line" \
                | sed 's/^[^=]*=[[:space:]]*//' \
                | sed 's/[[:space:]]*$//' \
                | sed -E 's/[[:space:]]+#.*$//' \
                | sed 's/^["'"'"']//' \
                | sed 's/["'"'"']$//')
            # Extract base model name - handle both @ and : properly
            local model_name
            local search_pattern
            if [[ "$model_ref" == *"@"* ]]; then
                # SHA reference: mistral-small3.2@sha256:... -> look for mistral-small3.2*
                local base_name
                base_name=$(echo "$model_ref" | cut -d'@' -f1)
                search_pattern="$base_name"
                # Try to find any version of this model in ollama list using exact field matching
                local found_line
                found_line=$(echo "$_ollama_list" | awk -v base_name="$base_name" '$1 ~ "^" base_name {print; exit}' || echo "")
                if [[ -n "$found_line" ]]; then
                    model_name=$(echo "$found_line" | awk '{print $1}')  # Use exact name from ollama
                else
                    model_name="$base_name (not found)"
                fi
            else
                # Regular reference: llama3.2:3b -> llama3.2:3b
                model_name="$model_ref"
                search_pattern="$model_ref"
            fi
            
            # Try to get size from ollama list using robust pattern-based matching
            local size_info
            size_info=$(echo "$_ollama_list" | awk -v pattern="$search_pattern" '
                NR > 1 && ($1 == pattern || index($1, pattern ":") == 1) {
                    # Strategy 1: Look for size pattern (number + unit) with space separation
                    size_found = ""
                    for (i = 1; i <= NF; i++) {
                        if ($i ~ /^[0-9]+(\.[0-9]+)?$/ && $(i+1) ~ /^([KMGT]?i?B)$/i) {
                            size_found = $i " " $(i+1)
                            break
                        }
                    }
                    
                    # Strategy 2: Look for compact size pattern (number+unit without space)
                    if (size_found == "") {
                        for (i = 1; i <= NF; i++) {
                            if ($i ~ /^[0-9]+(\.[0-9]+)?([KMGT]?i?B)$/i) {
                                # Extract number and unit parts with validation
                                if (match($i, /^([0-9]+(\.[0-9]+)?)([KMGT]?i?B)$/i)) {
                                    num_part = substr($i, 1, RSTART + RLENGTH - 1)
                                    gsub(/[KMGT]?i?B$/i, "", num_part)
                                    unit_part = $i
                                    gsub(/^[0-9.]+/, "", unit_part)
                                    # Validate extracted parts before using
                                    if (num_part ~ /^[0-9]+(\.[0-9]+)?$/ && unit_part ~ /^[KMGT]?i?B$/i) {
                                        size_found = num_part " " unit_part
                                        break
                                    }
                                }
                            }
                        }
                    }
                    
                    # Strategy 3: Fallback to traditional fields 3-4 with enhanced validation
                    if (size_found == "" && NF >= 4) {
                        # Validate that fields 3-4 look like a proper size before using them
                        if ($3 ~ /^[0-9]+(\.[0-9]+)?$/ && $4 ~ /^([KMGT]?i?B)$/i) {
                            size_found = $3 " " $4
                        }
                    }
                    
                    # Strategy 4: Last resort - regex extraction from entire line with validation
                    if (size_found == "") {
                        # Match spaced format: "4.2 GB" or "4.2 GiB"
                        if (match($0, /[0-9]+(\.[0-9]+)?\s+([KMGT]?i?B)/i)) {
                            size_found = substr($0, RSTART, RLENGTH)
                        }
                        # Match compact format: "4.2GB" or "4.2GiB"
                        else if (match($0, /[0-9]+(\.[0-9]+)?([KMGT]?i?B)/i)) {
                            matched_text = substr($0, RSTART, RLENGTH)
                            # Split into number and unit with validation
                            temp_num = matched_text
                            gsub(/[KMGT]?i?B$/i, "", temp_num)
                            temp_unit = substr($0, RSTART, RLENGTH)
                            gsub(/^[0-9.]+/, "", temp_unit)
                            # Only use if both parts are valid
                            if (temp_num ~ /^[0-9]+(\.[0-9]+)?$/ && temp_unit ~ /^[KMGT]?i?B$/i) {
                                size_found = temp_num " " temp_unit
                            }
                        }
                    }
                    
                    # Final guard: ensure size_found is non-empty and contains valid unit (SI or IEC)
                    if (size_found ~ /^[0-9]+(\.[0-9]+)?[[:space:]]+([KMGT]?i?B)$/i) {
                        print size_found
                    } else {
                        print ""
                    }
                    exit
                }
            ')
            
            if [[ -n "$size_info" ]]; then
                echo "  $model_name: $size_info"
                models_found=$((models_found + 1))
                total_display="$total_display$size_info, "
            else
                echo "  $model_name: Not found in Ollama"
            fi
        fi
    done < "$ENV_FILE"
    
    echo "Models found in Ollama: $models_found"
    if [[ -n "$total_display" ]]; then
        echo "Individual sizes: ${total_display%, }"
    fi
    echo "💡 Use 'ollama list' to compute total size dynamically at runtime"
    echo ""
    
    return 0  # Ensure successful return
}

# Main validation logic
main() {
    # Verify file exists
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "❌ ERROR: Environment file not found: $ENV_FILE"
        exit 1
    fi
    
    # Extract and display model references
    extract_model_references "$ENV_FILE"
    
    # Verify per-model inclusion against OLLAMA_MODELS_AVAILABLE
    verify_model_inclusion "$ENV_FILE"
    
    # Compute counts from both sources
    local count_from_vars
    count_from_vars=$(compute_model_count_from_vars "$ENV_FILE")
    local count_from_available
    count_from_available=$(compute_model_count_from_available "$ENV_FILE")
    
    echo "🔢 MODEL COUNT VALIDATION:"
    echo "  Count from OLLAMA_MODEL_* variables: $count_from_vars"
    echo "  Count from OLLAMA_MODELS_AVAILABLE: $count_from_available"
    
    # Validate consistency
    if [[ "$count_from_vars" -eq "$count_from_available" ]]; then
        echo "  ✅ Model counts are consistent"
    else
        echo "  ❌ ERROR: Model count mismatch!"
        echo "    Per-model variables: $count_from_vars"
        echo "    OLLAMA_MODELS_AVAILABLE: $count_from_available"
        
        if [[ "$VALIDATION_MODE" == "strict" ]]; then
            echo ""
            echo "🚫 DEPLOYMENT BLOCKED: Model configuration inconsistency detected"
            exit 1
        fi
    fi
    echo ""
    
    # Check for unpinned tags
    echo "🔍 CHECKING FOR UNPINNED TAGS:"
    local unpinned_found=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?OLLAMA_MODEL_[A-Za-z0-9_]+[[:space:]]*=[[:space:]]*[\"\']*.*:latest.*[\"\']*[[:space:]]*$ ]]; then
            echo "  ❌ Found unpinned tag: $line"
            unpinned_found=true
        fi
    done < "$ENV_FILE"
    
    if [[ "$unpinned_found" == "false" ]]; then
        echo "  ✅ No unpinned :latest tags found"
    elif [[ "$VALIDATION_MODE" == "strict" ]]; then
        echo ""
        echo "🚫 DEPLOYMENT BLOCKED: Unpinned model tags detected"
        exit 1
    fi
    echo ""
    
    # Compute total size if ollama is available
    if command -v ollama >/dev/null 2>&1; then
        compute_total_size
    else
        echo "📊 Ollama not available - skipping size calculation"
        echo ""
    fi
    
    echo "✅ MODEL CONFIGURATION VALIDATION COMPLETE"
    echo ""
    echo "💡 RUNTIME RECOMMENDATIONS:"
    echo "  - Use count_from_vars ($count_from_vars) for model count in runtime code"
    echo "  - Compute total size dynamically from 'ollama list' output"
    echo "  - Use OLLAMA_MODELS_AVAILABLE or per-model vars as single source of truth"
}

# Show usage if no args and file doesn't exist
if [[ $# -eq 0 ]] && [[ ! -f "$ENV_FILE" ]]; then
    echo "Usage: $0 [env_file] [validation_mode]"
    echo "  env_file: Path to ollama.env file (default: /opt/hx-infrastructure/llm-01/config/ollama/ollama.env)"
    echo "  validation_mode: strict|info (default: strict)"
    echo ""
    echo "Examples:"
    echo "  $0                                           # Validate default production file"
    echo "  $0 ./ollama.env                              # Validate specific file"
    echo "  $0 ./ollama.env info                         # Info mode (warnings only)"
    exit 1
fi

main
