#!/usr/bin/env bash

# HX-Infrastructure Authentication Token Manager  
# Single Responsibility: Handle authentication tokens for testing only
#
# This component manages authentication tokens used by test suites
# Following Single Responsibility Principle - handles ONLY token management

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"

# Compute security config directory path once
if [[ -n "${SECURITY_CONFIG_DIR:-}" ]]; then
    # Use environment variable if set
    security_config_dir="$SECURITY_CONFIG_DIR"
else
    # Save current directory
    original_pwd="$(pwd)"
    
    # Try to resolve relative path, fallback to hardcoded path
    if cd "$(dirname "${BASH_SOURCE[0]}")"/../../config/security 2>/dev/null; then
        security_config_dir="$(pwd)"
        cd "$original_pwd"
    else
        security_config_dir="/opt/HX-Infrastructure-/api-gateway/config/security"
    fi
fi

# Set readonly variables once
readonly SECURITY_CONFIG_DIR="$security_config_dir"
readonly TOKEN_FILE="${TOKEN_FILE:-$SECURITY_CONFIG_DIR/.test-tokens}"

# Single Responsibility: Token validation only
validate_token_format() {
    local token="$1"
    
    if [[ -z "$token" ]]; then
        echo "ERROR: Token cannot be empty"
        return 1
    fi
    
    if [[ ${#token} -lt 16 ]]; then
        echo "ERROR: Token must be at least 16 characters"
        return 1
    fi
    
    if [[ "$token" == *"sk-hx-dev"* ]]; then
        echo "WARNING: Development token detected"
    fi
    
    return 0
}

# Single Responsibility: Secure token storage only
store_test_token() {
    local token="$1"
    
    if ! validate_token_format "$token"; then
        return 1
    fi
    
    # Ensure security config directory exists
    mkdir -p "$SECURITY_CONFIG_DIR"
    
    # Secure directory permissions to prevent traversal/inspection
    chown hx-gateway:hx-gateway "$SECURITY_CONFIG_DIR" 2>/dev/null || true
    chmod 700 "$SECURITY_CONFIG_DIR"
    
    # Store token securely
    echo "$token" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    chown hx-gateway:hx-gateway "$TOKEN_FILE" 2>/dev/null || true
    
    echo "[${SCRIPT_NAME}] Test token stored securely"
    return 0
}

# Single Responsibility: Token retrieval only
get_test_token() {
    if [[ -f "$TOKEN_FILE" ]]; then
        # Safely read token file without executing code
        local token_content
        token_content=$(cat "$TOKEN_FILE" 2>/dev/null || echo "")
        
        # If it looks like a shell assignment, extract the value
        if [[ "$token_content" =~ ^[[:space:]]*AUTH_TOKEN=(.*)$ ]]; then
            local token_value="${BASH_REMATCH[1]}"
            # Remove surrounding quotes if present
            token_value="${token_value#\"}"
            token_value="${token_value%\"}"
            token_value="${token_value#\'}"
            token_value="${token_value%\'}"
            echo "$token_value"
        else
            # Assume it's a raw token
            echo "$token_content"
        fi
    else
        echo "${AUTH_TOKEN:-}"
    fi
}

# Single Responsibility: Token validation status only
check_token_status() {
    echo "[${SCRIPT_NAME}] Authentication Token Status"
    echo "==========================================="
    
    local current_token
    current_token=$(get_test_token)
    
    if [[ -n "$current_token" ]]; then
        if validate_token_format "$current_token"; then
            echo "✅ VALID: Test authentication token is properly configured"
            echo "   Token length: ${#current_token} characters"
            if [[ "$current_token" == *"sk-hx-dev"* ]]; then
                echo "⚠️  WARNING: Development token in use"
            fi
        else
            echo "❌ INVALID: Test authentication token format is invalid"
            return 1
        fi
    else
        echo "❌ MISSING: No test authentication token configured"
        echo "   Set with: export AUTH_TOKEN='your-token'"
        return 1
    fi
    
    return 0
}

# Single Responsibility: Generate secure token only
generate_secure_token() {
    local prefix="${1:-sk-hx-test}"
    local random_part
    if ! command -v openssl >/dev/null 2>&1; then
        echo "ERROR: openssl not found; cannot generate secure token" >&2
        return 1
    fi
    random_part=$(openssl rand -hex 16)
    echo "${prefix}-${random_part}"
}

# Main function - orchestrates single responsibility functions
main() {
    case "${1:-status}" in
        "generate")
            generate_secure_token "${2:-}"
            ;;
        "store")
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: Token required for store operation"
                echo "Usage: $SCRIPT_NAME store <token>"
                exit 1
            fi
            store_test_token "$2"
            ;;
        "get")
            get_test_token
            ;;
        "status")
            check_token_status
            ;;
        *)
            echo "Usage: $SCRIPT_NAME {generate [prefix]|store <token>|get|status}"
            echo "  generate [prefix] - Generate a secure token with optional prefix"
            echo "  store <token>     - Store token securely for testing"
            echo "  get               - Retrieve current test token"
            echo "  status            - Check token configuration status"
            exit 1
            ;;
    esac
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
