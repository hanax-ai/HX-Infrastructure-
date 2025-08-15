#!/bin/bash
# model-config.sh - Shared library for model configuration parsing
# Provides common functions for extracting and parsing OLLAMA model references

# Function to extract all model references from environment file
# Usage: extract_model_references <env_file_path>
# Outputs: Model registry analysis with individual variables and available models list
extract_model_references() {
    local env_file="$1"
    
    # Validate input argument
    if [[ -z "$env_file" ]]; then
        echo "Error: extract_model_references requires an environment file path" >&2
        return 1
    fi
    
    if [[ ! -f "$env_file" ]] || [[ ! -r "$env_file" ]]; then
        echo "Error: File '$env_file' does not exist or is not readable" >&2
        return 1
    fi
    
    echo "📋 MODEL REGISTRY ANALYSIS:"
    
    # Extract per-model variables with anchored matching
    echo "Individual model variables:"
    while IFS= read -r line; do
        # Only match anchored OLLAMA_MODEL_* variables, explicitly excluding OLLAMA_MODELS_*
        # Support both uppercase and lowercase letters in variable names
        if [[ "$line" =~ ^[[:space:]]*OLLAMA_MODEL_[A-Za-z0-9_]+[[:space:]]*= ]] && [[ ! "$line" =~ ^[[:space:]]*OLLAMA_MODELS_ ]]; then
            local var_name=$(echo "$line" | sed 's/^[[:space:]]*\([^=]*\)[[:space:]]*=.*/\1/')
            
            # Extract RHS value supporting both quoted and unquoted forms
            local var_value
            var_value=$(echo "$line" | sed 's/^[^=]*=[[:space:]]*//')
            
            # Detect if value is quoted and handle comments appropriately
            if [[ "$var_value" =~ ^[[:space:]]*[\"\'] ]]; then
                # Value is quoted - strip only surrounding quotes, preserve # inside quotes
                var_value=$(echo "$var_value" | sed 's/^[[:space:]]*["'"'"']//' | sed 's/["'"'"'][[:space:]]*#.*$//' | sed 's/["'"'"'][[:space:]]*$//')
            else
                # Value is unquoted - remove trailing comments and trim whitespace
                var_value=$(echo "$var_value" | sed 's/[[:space:]]*#.*$//' | sed 's/[[:space:]]*$//')
            fi
            
            echo "  $var_name = $var_value"
        fi
    done < "$env_file"
    
    # Extract available models list with anchored matching and quote handling
    local available_models
    available_models=$(grep "^[[:space:]]*OLLAMA_MODELS_AVAILABLE[[:space:]]*=" "$env_file" 2>/dev/null | tail -n1 | sed 's/^[^=]*=[[:space:]]*//' || echo "")
    
    # Handle comments and quotes more carefully for available models
    # If the value starts with quotes, preserve content until closing quote
    if [[ "$available_models" =~ ^[[:space:]]*[\"\'] ]]; then
        # Extract quoted content and strip external comments after closing quote
        local quote_char="${available_models:0:1}"
        if [[ "$quote_char" == " " ]]; then
            available_models="${available_models#"${available_models%%[![:space:]]*}"}"  # Trim leading space
            quote_char="${available_models:0:1}"
        fi
        
        # Find the content between quotes
        if [[ "$quote_char" == "\"" ]]; then
            available_models=$(echo "$available_models" | sed 's/^[[:space:]]*"//' | sed 's/"[[:space:]]*#.*$//' | sed 's/"[[:space:]]*$//')
        elif [[ "$quote_char" == "'" ]]; then
            available_models=$(echo "$available_models" | sed "s/^[[:space:]]*'//" | sed "s/'[[:space:]]*#.*$//" | sed "s/'[[:space:]]*$//")
        fi
    else
        # Unquoted value - strip comments and trim whitespace
        available_models=$(echo "$available_models" | sed 's/[[:space:]]*#.*$//' | sed 's/[[:space:]]*$//')
    fi
    
    echo "Available models list: $available_models"
    echo ""
}

# Helper function to extract model value from a configuration line
# Usage: extract_model_value <config_line>
# Returns: The cleaned model value (quotes stripped, comments removed)
extract_model_value() {
    local line="$1"
    
    if [[ -z "$line" ]]; then
        echo ""
        return 1
    fi
    
    # Extract RHS value
    local var_value
    var_value=$(echo "$line" | sed 's/^[^=]*=[[:space:]]*//')
    
    # Detect if value is quoted and handle comments appropriately
    if [[ "$var_value" =~ ^[[:space:]]*[\"\'] ]]; then
        # Value is quoted - strip only surrounding quotes, preserve # inside quotes
        var_value=$(echo "$var_value" | sed 's/^[[:space:]]*["'"'"']//' | sed 's/["'"'"'][[:space:]]*#.*$//' | sed 's/["'"'"'][[:space:]]*$//')
    else
        # Value is unquoted - remove trailing comments and trim whitespace
        var_value=$(echo "$var_value" | sed 's/[[:space:]]*#.*$//' | sed 's/[[:space:]]*$//')
    fi
    
    echo "$var_value"
}

# Helper function to check if a line matches OLLAMA_MODEL_* pattern
# Usage: is_model_variable <config_line>
# Returns: 0 if matches, 1 if not
is_model_variable() {
    local line="$1"
    
    if [[ -z "$line" ]]; then
        return 1
    fi
    
    # Check if line matches OLLAMA_MODEL_* pattern but excludes OLLAMA_MODELS_*
    if [[ "$line" =~ ^[[:space:]]*OLLAMA_MODEL_[A-Za-z0-9_]+[[:space:]]*= ]] && [[ ! "$line" =~ ^[[:space:]]*OLLAMA_MODELS_ ]]; then
        return 0
    else
        return 1
    fi
}
