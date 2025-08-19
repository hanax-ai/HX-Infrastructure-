#!/bin/bash

# Source shared model configuration library with robust path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Search for model-config.sh in likely locations
MODEL_CONFIG_PATHS=(
    "$SCRIPT_DIR/../lib/model-config.sh"
    "$SCRIPT_DIR/../../lib/model-config.sh"
    "$SCRIPT_DIR/../../../lib/model-config.sh"
    "$SCRIPT_DIR/lib/model-config.sh"
)

# Check if MODEL_CONFIG_LIB is explicitly set and readable
if [[ -n "${MODEL_CONFIG_LIB:-}" && -r "${MODEL_CONFIG_LIB}" ]]; then
    # Use explicit override if it's set and readable
    echo "Using explicit MODEL_CONFIG_LIB: $MODEL_CONFIG_LIB"
else
    # Fall back to searching standard paths
    MODEL_CONFIG_LIB=""
    for path in "${MODEL_CONFIG_PATHS[@]}"; do
        if [[ -r "$path" ]]; then
            MODEL_CONFIG_LIB="$path"
            break
        fi
    done
fi

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

# Validate env file argument
if [[ -z "$1" ]]; then
    echo "Usage: test-extraction.sh <env-file>" >&2
    exit 1
fi

if [[ ! -f "$1" ]] || [[ ! -r "$1" ]]; then
    echo "Usage: test-extraction.sh <env-file>" >&2
    echo "Error: File '$1' does not exist or is not readable" >&2
    exit 1
fi

echo "Testing: $1"
extract_model_references "$1"
