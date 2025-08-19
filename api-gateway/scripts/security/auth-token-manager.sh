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
        echo "ERROR: Token cannot be empty" >&2
        return 1
    fi
    
    if [[ ${#token} -lt 16 ]]; then
        echo "ERROR: Token must be at least 16 characters" >&2
        return 1
    fi
    
    if [[ "$token" == *"sk-hx-dev"* ]]; then
        echo "WARNING: Development token detected" >&2
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
    
    # Store token securely with atomic write
    local previous_umask
    previous_umask=$(umask)
    umask 077  # Restrictive permissions during creation
    
    local temp_file
    temp_file=$(mktemp "${TOKEN_FILE}.XXXXXX")
    
    # Set up cleanup trap
    trap 'rm -f "$temp_file"; umask "$previous_umask"' EXIT ERR
    
    # Write token without trailing newline
    printf '%s' "$token" > "$temp_file"
    
    # Set final permissions and ownership
    chmod 600 "$temp_file"
    chown hx-gateway:hx-gateway "$temp_file" 2>/dev/null || true
    
    # Atomic move to final location
    mv "$temp_file" "$TOKEN_FILE"
    
    # Clean up trap and restore umask
    trap - EXIT ERR
    umask "$previous_umask"
    
    echo "[${SCRIPT_NAME}] Test token stored securely"
    return 0
}

# Single Responsibility: Token retrieval only
get_test_token() {
    if [[ -f "$TOKEN_FILE" ]]; then
        # Safely read token file line by line without executing code
        local token_value=""
        local line
        
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip empty lines and comments
            [[ -z "$line" ]] && continue
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            
            # Look for AUTH_TOKEN assignment with optional "export" prefix
            if [[ "$line" =~ ^([[:space:]]*export[[:space:]]+)?AUTH_TOKEN[[:space:]]*=[[:space:]]*([^#]*)(#.*)?$ ]]; then
                token_value="${BASH_REMATCH[2]}"
                # Trim leading and trailing whitespace
                token_value="${token_value#"${token_value%%[![:space:]]*}"}"
                token_value="${token_value%"${token_value##*[![:space:]]}"}"
                # Remove surrounding quotes if present (single or double)
                if [[ "$token_value" =~ ^\"(.*)\"$ ]] || [[ "$token_value" =~ ^\'(.*)\'$ ]]; then
                    token_value="${BASH_REMATCH[1]}"
                fi
                # Explicitly strip trailing newlines and carriage returns
                token_value="${token_value%$'\n'}"
                token_value="${token_value%$'\r'}"
                # Only return if token is non-empty
                if [[ -n "$token_value" ]]; then
                    echo "$token_value"
                    return 0
                fi
            fi
        done < "$TOKEN_FILE"
        
        # If no AUTH_TOKEN= found, treat entire first non-empty line as raw token
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" ]] && continue
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            # Strip trailing newlines and carriage returns from raw token
            line="${line%$'\n'}"
            line="${line%$'\r'}"
            # Trim whitespace from raw token
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            # Only return if token is non-empty
            if [[ -n "$line" ]]; then
                echo "$line"
                return 0
            fi
        done < "$TOKEN_FILE"
    fi
    
    # Fallback to environment variable AUTH_TOKEN
    if [[ -n "${AUTH_TOKEN:-}" ]]; then
        echo "$AUTH_TOKEN"
        return 0
    fi
    
    # No token found anywhere - fail with clear error
    echo "ERROR: No authentication token found in $TOKEN_FILE or AUTH_TOKEN environment variable" >&2
    return 1
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
    
    # Attempt OpenSSL first (preferred method)
    if command -v openssl >/dev/null 2>&1; then
        random_part=$(openssl rand -hex 16)
        echo "${prefix}-${random_part}"
        return 0
    fi
    
    # Fallback: use /dev/urandom with hex conversion
    if [[ ! -r /dev/urandom ]]; then
        echo "ERROR: /dev/urandom not available; cannot generate secure token" >&2
        return 1
    fi
    
    # Try different hex conversion tools in order of preference
    if command -v xxd >/dev/null 2>&1; then
        random_part=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | xxd -p | tr -d '\n')
    elif command -v od >/dev/null 2>&1; then
        random_part=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | od -A n -t x1 | tr -d ' \n')
    elif command -v hexdump >/dev/null 2>&1; then
        random_part=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | hexdump -v -e '/1 "%02x"')
    else
        echo "ERROR: No hex conversion tool available (xxd, od, or hexdump required)" >&2
        return 1
    fi
    
    # Verify we got a proper hex string
    if [[ -z "$random_part" ]] || [[ ! "$random_part" =~ ^[0-9a-f]{32}$ ]]; then
        echo "ERROR: Failed to generate proper random hex string" >&2
        return 1
    fi
    
    echo "${prefix}-${random_part}"
    return 0
}

# Main function - orchestrates single responsibility functions
main() {
    case "${1:-status}" in
        "generate")
            generate_secure_token "${2:-}"
            ;;
        "store")
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: Token required for store operation" >&2
                echo "Usage: $SCRIPT_NAME store <token>" >&2
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
