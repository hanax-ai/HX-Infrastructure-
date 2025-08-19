#!/bin/bash

# Source shared model configuration library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/model-config.sh"

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
