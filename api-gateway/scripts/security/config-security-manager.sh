#!/usr/bin/env bash

# HX-Infrastructure Configuration Security Manager
# Single Responsibility: Manage secure configuration loading only
# 
# This component validates and loads secure configuration for the API Gateway
# Following Single Responsibility Principle - handles ONLY configuration security

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Derive paths from script location with environment variable overrides for portability
readonly CONFIG_DIR="${CONFIG_DIR:-$(cd "$SCRIPT_DIR/../../config/api-gateway" 2>/dev/null && pwd || echo "$SCRIPT_DIR/../../config/api-gateway")}"
readonly SECURITY_CONFIG_DIR="${SECURITY_CONFIG_DIR:-$(cd "$SCRIPT_DIR/../../config/security" 2>/dev/null && pwd || echo "$SCRIPT_DIR/../../config/security")}"

export CONFIG_DIR SECURITY_CONFIG_DIR

# Single Responsibility: Configuration validation only
validate_config_security() {
    local config_file="$1"
    
    echo "[${SCRIPT_NAME}] Validating configuration security: $config_file"
    
    # Check for hardcoded secrets
    if grep -q "sk-hx-dev" "$config_file" 2>/dev/null; then
        echo "ERROR: Hardcoded development key found in $config_file"
        return 1
    fi
    
    # Verify environment variable usage
    if ! grep -q "MASTER_KEY" "$config_file" 2>/dev/null; then
        echo "ERROR: MASTER_KEY environment variable not configured in $config_file"
        return 1
    fi
    
    echo "[${SCRIPT_NAME}] Configuration security validation passed: $config_file"
    return 0
}

# Single Responsibility: Environment variable validation only  
validate_environment_variables() {
    echo "[${SCRIPT_NAME}] Validating required environment variables"
    
    if [[ -z "${MASTER_KEY:-}" ]]; then
        echo "ERROR: MASTER_KEY environment variable is not set"
        echo "Set with: export MASTER_KEY='your-secure-key'"
        return 1
    fi
    
    if [[ "${MASTER_KEY}" == *"sk-hx-dev"* ]]; then
        echo "WARNING: Development key detected in MASTER_KEY"
        echo "Use a production-grade key for production deployment"
    fi
    
    echo "[${SCRIPT_NAME}] Environment variables validation passed"
    return 0
}

# Single Responsibility: Configuration file security status only
check_config_security_status() {
    echo "[${SCRIPT_NAME}] Configuration Security Status Check"
    echo "=================================================="
    
    local config_files=(
        "$CONFIG_DIR/config.yaml"
        "$CONFIG_DIR/config-complete.yaml" 
        "$CONFIG_DIR/config-extended.yaml"
    )
    
    local all_secure=true
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            if validate_config_security "$config_file"; then
                echo "✅ SECURE: $config_file"
            else
                echo "❌ INSECURE: $config_file"
                all_secure=false
            fi
        else
            echo "⚠️  NOT FOUND: $config_file"
        fi
    done
    
    if [[ "$all_secure" == "true" ]]; then
        echo "[${SCRIPT_NAME}] All configuration files are secure"
        return 0
    else
        echo "[${SCRIPT_NAME}] Security issues found in configuration files"
        return 1
    fi
}

# Main function - orchestrates single responsibility functions
main() {
    case "${1:-status}" in
        "validate-config")
            if [ -z "${2:-}" ]; then
                echo "Usage: $SCRIPT_NAME validate-config <file>"
                echo "  validate-config <file> - Validate specific config file security"
                exit 1
            fi
            validate_config_security "$2"
            ;;
        "validate-env")
            validate_environment_variables
            ;;
        "status")
            check_config_security_status
            ;;
        *)
            echo "Usage: $SCRIPT_NAME {validate-config <file>|validate-env|status}"
            echo "  validate-config <file> - Validate specific config file security"
            echo "  validate-env           - Validate environment variables"
            echo "  status                 - Check overall security status"
            exit 1
            ;;
    esac
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
