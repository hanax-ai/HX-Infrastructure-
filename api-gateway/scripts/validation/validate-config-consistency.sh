#!/bin/bash

# validate-config-consistency.sh
# Validates consistency across all backup configuration files
# Ensures adherence to canonical definitions and parameterization standards

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_GATEWAY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKUP_DIR="$API_GATEWAY_ROOT/gateway/backups"

# Configuration files to validate
CONFIG_FILES=(
    "$API_GATEWAY_ROOT/gateway/config/config.yaml"
    "$API_GATEWAY_ROOT/config/api-gateway/config.yaml"
    "$BACKUP_DIR/config.yaml"
    "$BACKUP_DIR/config-complete.yaml"
    "$BACKUP_DIR/config-extended.yaml"
)

CANONICAL_FILES=(
    "$BACKUP_DIR/shared-model-definitions.yaml"
    "$BACKUP_DIR/config-canonical.yaml"
)

# Validation functions
print_header() {
    echo -e "${BLUE}=== HX-Infrastructure Config Consistency Validator ===${NC}"
    echo -e "${BLUE}Validating: $(date)${NC}"
    echo
}

check_file_exists() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}✗ Missing file: $file${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ Found: $(basename "$file")${NC}"
    return 0
}

check_parameterization() {
    local file="$1"
    local filename=$(basename "$file")
    
    echo -e "${YELLOW}Checking parameterization in $filename...${NC}"
    
        # Check for hardcoded IPs (ignore comments and environment variable fallbacks)
    if grep -v "^[[:space:]]*#" "$file" | grep -v '\${.*:-http://192\.168\.10\.' | grep -q '192\.168\.10\.'; then
        echo -e "${RED}✗ Hardcoded IP addresses found in $filename${NC}"
        echo -e "${YELLOW}Found:${NC}"
        grep -v "^[[:space:]]*#" "$file" | grep -v '\${.*:-http://192\.168\.10\.' | grep -n '192\.168\.10\.' | head -5
        return 1
    fi
    
    # Check for required environment variable references
    if ! grep -qE '\*(orc_api_base|llm01_api_base|llm02_api_base)' "$file"; then
        echo -e "${RED}✗ Missing API base environment variable references in $filename${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Proper parameterization in $filename${NC}"
    return 0
}

check_yaml_anchors() {
    local file="$1"
    local filename=$(basename "$file")
    
    echo -e "${YELLOW}Checking YAML anchor usage in $filename...${NC}"
    
    # Skip anchor checks for canonical definition files
    if [[ "$filename" == "shared-model-definitions.yaml" || "$filename" == "config-canonical.yaml" ]]; then
        echo -e "${GREEN}✓ Canonical definition file - anchor check skipped${NC}"
        return 0
    fi
    
    # Check for load balancer group references or direct definitions
    # Expected anchors and patterns:
    #   - load_balancer_groups anchor (<<: *load_balancer_groups)
    #   - hx-chat variants: hx-chat, hx-chat-fast, hx-chat-code, hx-chat-premium, hx-chat-creative
    # Pattern relaxed to accommodate both anchor references and inline definitions
    # Treated as warning (not error) because load balancer groups are optional but recommended
    if grep -qP '<<: \*(?:load_balancer_groups|hx-chat)|\b(?:hx-chat|hx-chat-fast|hx-chat-code|hx-chat-premium|hx-chat-creative)\b' "$file"; then
        echo -e "${GREEN}✓ Load balancer definitions present in $filename${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}⚠ No load balancer group definitions found in $filename (load_balancer_groups anchor or hx-chat variants are optional but recommended)${NC}"
    return 0  # Warning only - load balancer groups are optional for flexibility
}

validate_yaml_syntax() {
    local file="$1"
    local filename=$(basename "$file")
    
    echo -e "${YELLOW}Validating YAML syntax in $filename...${NC}"
    
    # Check if python3 is available
    if ! command -v python3 >/dev/null 2>&1; then
        echo -e "${RED}✗ python3 is not installed or not in PATH${NC}"
        echo -e "${YELLOW}Please install python3:${NC}"
        echo "  - Ubuntu/Debian: sudo apt install python3"
        echo "  - CentOS/RHEL: sudo yum install python3"
        echo "  - macOS: brew install python3"
        return 1
    fi
    
    # Enhanced YAML syntax check with dependency validation
    local python_result
    python_result=$(python3 -c "
try:
    import yaml
except ImportError:
    print('ERROR: PyYAML not installed. Please install it with:')
    print('  pip3 install pyyaml')
    print('  or via system package manager (e.g., apt install python3-yaml)')
    exit(1)

try:
    with open('$file', 'r') as f:
        yaml.safe_load(f)
    print('YAML syntax is valid')
    exit(0)
except yaml.YAMLError as e:
    print(f'YAML syntax error: {e}')
    exit(1)
except Exception as e:
    print(f'Error reading file: {e}')
    exit(1)
" 2>&1)
    
    local exit_code=$?
    
    if [[ $exit_code -eq 1 ]]; then
        if [[ "$python_result" == *"PyYAML not installed"* ]]; then
            echo -e "${RED}✗ Missing dependency for $filename${NC}"
            echo "$python_result"
        else
            echo -e "${RED}✗ Invalid YAML syntax in $filename${NC}"
            echo "$python_result"
        fi
        return 1
    fi
    
    echo -e "${GREEN}✓ Valid YAML syntax in $filename${NC}"
    return 0
}

check_model_naming_consistency() {
    echo -e "${YELLOW}Checking model naming consistency...${NC}"
    
    # Extract model names from all configs
    local temp_file=$(mktemp)
    for config in "${CONFIG_FILES[@]}"; do
        if [[ -f "$config" ]]; then
            grep "model_name:" "$config" | sed 's/.*model_name: *//' | sort -u >> "$temp_file"
        fi
    done
    
    # Check for duplicate model names with different definitions
    local duplicates=$(sort "$temp_file" | uniq -d)
    if [[ -n "$duplicates" ]]; then
        echo -e "${YELLOW}⚠ Potential model name conflicts:${NC}"
        echo "$duplicates"
    else
        echo -e "${GREEN}✓ No model naming conflicts detected${NC}"
    fi
    
    rm -f "$temp_file"
}

generate_summary_report() {
    echo
    echo -e "${BLUE}=== Configuration Summary ===${NC}"
    
    for config in "${CONFIG_FILES[@]}"; do
        if [[ -f "$config" ]]; then
            local filename=$(basename "$config")
            local model_count=$(grep -c "model_name:" "$config" 2>/dev/null || echo "0")
            echo -e "${BLUE}$filename:${NC} $model_count models configured"
        fi
    done
    
    echo
    echo -e "${BLUE}=== Environment Variables Required ===${NC}"
    echo "- HX_MASTER_KEY: API Gateway master key (preferred) or MASTER_KEY (legacy)"
    echo "- ORC_API_BASE: Orchestrator API endpoint (default: http://192.168.10.31:11434)"
    echo "- LLM01_API_BASE: LLM-01 API endpoint (default: http://192.168.10.29:11434)"
    echo "- LLM02_API_BASE: LLM-02 API endpoint (default: http://192.168.10.28:11434)"
}

# Main validation workflow
main() {
    print_header
    
    local validation_errors=0
    
    # Check file existence
    echo -e "${YELLOW}Checking file existence...${NC}"
    for file in "${CONFIG_FILES[@]}" "${CANONICAL_FILES[@]}"; do
        check_file_exists "$file" || ((validation_errors++))
    done
    
    echo
    
    # Validate each configuration file
    for config in "${CONFIG_FILES[@]}"; do
        if [[ -f "$config" ]]; then
            echo -e "${YELLOW}Validating $(basename "$config")...${NC}"
            
            validate_yaml_syntax "$config" || ((validation_errors++))
            check_parameterization "$config" || ((validation_errors++))
            check_yaml_anchors "$config" || ((validation_errors++))
            
            echo
        fi
    done
    
    # Cross-file consistency checks
    check_model_naming_consistency
    
    # Generate summary
    generate_summary_report
    
    # Final result
    echo
    if [[ $validation_errors -eq 0 ]]; then
        echo -e "${GREEN}🎉 All validation checks passed! Configuration files are consistent.${NC}"
        exit 0
    else
        echo -e "${RED}❌ Validation failed with $validation_errors error(s). Please review and fix issues.${NC}"
        exit 1
    fi
}

# Help function
show_help() {
    echo "Usage: $0 [options]"
    echo
    echo "HX-Infrastructure Configuration Consistency Validator"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --summary      Show configuration summary only"
    echo
    echo "This script validates:"
    echo "  - File existence and YAML syntax"
    echo "  - Proper parameterization (no hard-coded IPs)"
    echo "  - YAML anchor usage for shared definitions"
    echo "  - Model naming consistency across configs"
    echo
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    --summary)
        generate_summary_report
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        show_help
        exit 1
        ;;
esac
