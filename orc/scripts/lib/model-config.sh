#!/bin/bash
# model-config.sh - Shared model configuration library
# Provides reusable functions for parsing and extracting model configuration

# Execution guard: This file is meant to be sourced, not executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This is a library file and should be sourced, not executed directly" >&2
    echo "Usage: source ${BASH_SOURCE[0]}" >&2
    exit 1
fi

# Function to extract model references from environment files
extract_model_references() {
    local env_file="$1"
    
    # Parameter validation
    if [[ -z "$env_file" ]]; then
        echo "ERROR: env_file parameter is required" >&2
        echo "Usage: extract_model_references <env_file>" >&2
        return 2
    fi
    
    # File existence and readability check
    if [[ ! -f "$env_file" ]]; then
        echo "ERROR: File does not exist: $env_file" >&2
        return 1
    fi
    
    if [[ ! -r "$env_file" ]]; then
        echo "ERROR: File is not readable: $env_file" >&2
        return 1
    fi
    
    # Normal operation - output to stdout for machine parsing
    echo "Extracting model references from: $env_file"
    # Mock implementation for testing
    echo "Mock extract_model_references function executed"
    
    # Success
    return 0
}

# Additional shared functions can be added here
