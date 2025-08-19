#!/usr/bin/env bash

# HX-Infrastructure Service Configuration Validator
# Single Responsibility: Validate service configurations only
#
# This component validates service configuration completeness and correctness
# Following Single Responsibility Principle - handles ONLY service config validation

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly CONFIG_DIR="/opt/HX-Infrastructure-/api-gateway/config/api-gateway"
readonly SERVICE_NAME="hx-litellm-gateway"

# Single Responsibility: Environment prerequisites validation only
validate_environment_prerequisites() {
    echo "[${SCRIPT_NAME}] Validating environment prerequisites"
    
    local required_vars=(
        "MASTER_KEY"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "ERROR: Missing required environment variables:"
        printf "  - %s\n" "${missing_vars[@]}"
        return 1
    fi
    
    echo "[${SCRIPT_NAME}] Environment prerequisites validation passed"
    return 0
}

# Single Responsibility: Configuration file syntax validation only
validate_config_syntax() {
    local config_file="$1"
    
    echo "[${SCRIPT_NAME}] Validating configuration syntax: $config_file"
    
    # Check if file exists and is readable
    if [[ ! -f "$config_file" || ! -r "$config_file" ]]; then
        echo "ERROR: Configuration file does not exist or is not readable: $config_file"
        return 1
    fi
    
    # Validate YAML syntax and required sections with proper parsing
    local python_result
    python_result=$(python3 -c "
import sys
import yaml

try:
    with open(sys.argv[1], 'r') as f:
        config = yaml.safe_load(f)
except yaml.YAMLError as e:
    print(f'YAML parse error: {e}')
    sys.exit(1)
except Exception as e:
    print(f'Error reading file: {e}')
    sys.exit(1)

if config is None:
    print('ERROR: Empty YAML file')
    sys.exit(1)

# Check for required top-level keys
required_keys = ['general_settings', 'model_list']
for key in required_keys:
    if key not in config:
        print(f'ERROR: Missing {key} section')
        sys.exit(1)
    if config[key] is None or (isinstance(config[key], (list, dict)) and len(config[key]) == 0):
        print(f'ERROR: Empty {key} section')
        sys.exit(1)

print('YAML validation passed')
" "$config_file" 2>&1)
    
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        if [[ "$python_result" == *"Missing general_settings section"* ]]; then
            echo "ERROR: Missing general_settings section in $config_file"
        elif [[ "$python_result" == *"Missing model_list section"* ]]; then
            echo "ERROR: Missing model_list section in $config_file"
        elif [[ "$python_result" == *"Empty general_settings section"* ]]; then
            echo "ERROR: Empty general_settings section in $config_file"
        elif [[ "$python_result" == *"Empty model_list section"* ]]; then
            echo "ERROR: Empty model_list section in $config_file"
        else
            echo "ERROR: YAML validation failed for $config_file"
            echo "$python_result"
        fi
        return 1
    fi
    
    echo "[${SCRIPT_NAME}] Configuration syntax validation passed: $config_file"
    return 0
}

# Single Responsibility: Service readiness validation only
validate_service_readiness() {
    echo "[${SCRIPT_NAME}] Validating service readiness"
    
    # Check if service user exists
    if ! id hx-gateway &>/dev/null; then
        echo "ERROR: Service user 'hx-gateway' does not exist"
        echo "Create with: sudo useradd -r -s /bin/false hx-gateway"
        return 1
    fi
    
    # Check directory permissions
    local gateway_dir="/opt/HX-Infrastructure-/api-gateway/gateway"
    if [[ ! -d "$gateway_dir" ]]; then
        echo "ERROR: Gateway directory does not exist: $gateway_dir"
        return 1
    fi
    
    # Check if systemd service file exists
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
    if [[ ! -f "$service_file" ]]; then
        echo "WARNING: Systemd service file not found: $service_file"
    fi
    
    echo "[${SCRIPT_NAME}] Service readiness validation passed"
    return 0
}

# Single Responsibility: Complete configuration validation only
validate_complete_configuration() {
    echo "[${SCRIPT_NAME}] Complete Configuration Validation"
    echo "==============================================="
    
    local validation_failed=false
    
    # Validate environment
    if ! validate_environment_prerequisites; then
        validation_failed=true
    fi
    
    # Validate configuration files
    local config_files=(
        "$CONFIG_DIR/config.yaml"
        "$CONFIG_DIR/config-complete.yaml"
    )
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            if ! validate_config_syntax "$config_file"; then
                validation_failed=true
            fi
        fi
    done
    
    # Validate service readiness
    if ! validate_service_readiness; then
        validation_failed=true
    fi
    
    if $validation_failed; then
        echo "[${SCRIPT_NAME}] Configuration validation FAILED"
        return 1
    else
        echo "[${SCRIPT_NAME}] Configuration validation PASSED"
        return 0
    fi
}

# Single Responsibility: Generate validation report only
generate_validation_report() {
    echo "[${SCRIPT_NAME}] Service Configuration Validation Report"
    echo "====================================================="
    echo "Generated: $(date)"
    echo
    
    # Environment status
    echo "Environment Variables:"
    if [[ -n "${MASTER_KEY:-}" ]]; then
        echo "  ✅ MASTER_KEY: Configured (${#MASTER_KEY} chars)"
    else
        echo "  ❌ MASTER_KEY: Not configured"
    fi
    echo
    
    # Configuration files status
    echo "Configuration Files:"
    local config_files=(
        "$CONFIG_DIR/config.yaml"
        "$CONFIG_DIR/config-complete.yaml"
        "$CONFIG_DIR/config-extended.yaml"
    )
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            if validate_config_syntax "$config_file" &>/dev/null; then
                echo "  ✅ $(basename "$config_file"): Valid"
            else
                echo "  ❌ $(basename "$config_file"): Invalid"
            fi
        else
            echo "  ⚠️  $(basename "$config_file"): Not found"
        fi
    done
    echo
    
    # Service readiness
    echo "Service Readiness:"
    if validate_service_readiness &>/dev/null; then
        echo "  ✅ Service prerequisites met"
    else
        echo "  ❌ Service prerequisites not met"
    fi
}

# Main function - orchestrates single responsibility functions
main() {
    case "${1:-validate}" in
        "validate-env")
            validate_environment_prerequisites
            ;;
        "validate-config")
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: Configuration file required"
                echo "Usage: $SCRIPT_NAME validate-config <file>"
                exit 1
            fi
            validate_config_syntax "$2"
            ;;
        "validate-service")
            validate_service_readiness
            ;;
        "validate")
            validate_complete_configuration
            ;;
        "report")
            generate_validation_report
            ;;
        *)
            echo "Usage: $SCRIPT_NAME {validate-env|validate-config <file>|validate-service|validate|report}"
            echo "  validate-env         - Validate environment variables"
            echo "  validate-config <f>  - Validate specific config file"
            echo "  validate-service     - Validate service readiness"
            echo "  validate             - Complete validation"
            echo "  report               - Generate validation report"
            exit 1
            ;;
    esac
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
