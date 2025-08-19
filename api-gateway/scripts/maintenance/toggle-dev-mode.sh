#!/usr/bin/env bash
set -euo pipefail

# HX-Infrastructure API Gateway - Development Mode Toggle
# This script switches between production-secure and development-friendly permissions

API_GATEWAY_DIR="${API_GATEWAY_DIR:-/opt/HX-Infrastructure-/api-gateway}"
GATEWAY_USER="${GATEWAY_USER:-hx-gateway}"
DEV_USER="${DEV_USER:-${SUDO_USER:-$(whoami)}}"

show_help() {
    echo "Usage: $(basename "$0") [enable|disable|status]"
    echo ""
    echo "Commands:"
    echo "  enable   - Enable development mode (VS Code editing allowed)"
    echo "  disable  - Disable development mode (production security)"
    echo "  status   - Show current permission status"
    echo ""
    echo "Development mode allows VS Code editing but reduces security."
    echo "Always disable before production deployment!"
}

show_status() {
    echo "=== API Gateway Permission Status ==="
    echo ""
    
    # Check ownership of key directories (user:group)
    local config_owner
    local scripts_owner
    local docs_owner
    local gateway_owner
    config_owner=$(stat -c '%U:%G' "$API_GATEWAY_DIR/config" 2>/dev/null || echo "unknown:unknown")
    scripts_owner=$(stat -c '%U:%G' "$API_GATEWAY_DIR/scripts" 2>/dev/null || echo "unknown:unknown")
    docs_owner=$(stat -c '%U:%G' "$API_GATEWAY_DIR/x-Docs" 2>/dev/null || echo "unknown:unknown")
    gateway_owner=$(stat -c '%U:%G' "$API_GATEWAY_DIR/gateway" 2>/dev/null || echo "unknown:unknown")
    
    # Extract user and group for mode detection
    local config_user
    local config_group
    config_user=$(echo "$config_owner" | cut -d: -f1)
    config_group=$(echo "$config_owner" | cut -d: -f2)
    
    if [[ "$config_user" == "$DEV_USER" ]]; then
        echo "🟡 DEVELOPMENT MODE: VS Code editing enabled"
        echo "   Owner: $config_owner (development)"
        echo "   Security: Reduced (development only)"
    elif [[ "$config_user" == "root" && "$config_group" == "$GATEWAY_USER" ]]; then
        echo "🔒 PRODUCTION MODE: Production security active"
        echo "   Owner: root:$GATEWAY_USER (production)"
        echo "   Security: Hardened (production ready)"
    else
        echo "⚠️  UNKNOWN MODE: Unexpected ownership"
        echo "   Owner: $config_owner"
    fi
    
    echo ""
    echo "Directory owners:"
    echo "  config/: $config_owner"
    echo "  scripts/: $scripts_owner" 
    echo "  x-Docs/: $docs_owner"
    echo "  gateway/: $gateway_owner"
}

enable_dev_mode() {
    echo "🟡 Enabling development mode..."
    echo ""
    
    # Change ownership to allow VS Code editing
    echo "--> Setting development-friendly ownership..."
    test -d "$API_GATEWAY_DIR/config" && sudo chown -R "$DEV_USER:$DEV_USER" "$API_GATEWAY_DIR/config"
    test -d "$API_GATEWAY_DIR/scripts" && sudo chown -R "$DEV_USER:$DEV_USER" "$API_GATEWAY_DIR/scripts"
    test -d "$API_GATEWAY_DIR/x-Docs" && sudo chown -R "$DEV_USER:$DEV_USER" "$API_GATEWAY_DIR/x-Docs"
    test -d "$API_GATEWAY_DIR/gateway" && sudo chown -R "$DEV_USER:$DEV_USER" "$API_GATEWAY_DIR/gateway"
    
    # Set permissive permissions for development
    if test -d "$API_GATEWAY_DIR/scripts"; then
        sudo find "$API_GATEWAY_DIR/scripts" -type d -exec chmod 755 {} \;
        sudo find "$API_GATEWAY_DIR/scripts" -type f -exec chmod 644 {} \;
    fi
    if test -d "$API_GATEWAY_DIR/config"; then
        sudo find "$API_GATEWAY_DIR/config" -type d -exec chmod 755 {} \;
        sudo find "$API_GATEWAY_DIR/config" -type f -exec chmod 644 {} \;
    fi
    if test -d "$API_GATEWAY_DIR/x-Docs"; then
        sudo find "$API_GATEWAY_DIR/x-Docs" -type d -exec chmod 755 {} \;
        sudo find "$API_GATEWAY_DIR/x-Docs" -type f -exec chmod 644 {} \;
    fi
    
    # Make sure service scripts remain executable (if directory exists)
    if [ -d "$API_GATEWAY_DIR/scripts" ]; then
        find "$API_GATEWAY_DIR/scripts" -name "*.sh" -exec sudo chmod +x {} \;
    fi
    
    echo "✅ Development mode enabled"
    echo "   VS Code can now edit configuration files"
    echo "   ⚠️  Remember to disable before production deployment!"
}

disable_dev_mode() {
    echo "🔒 Disabling development mode (production security)..."
    echo ""
    
    # Revert to production ownership
    echo "--> Setting production-secure ownership..."
    if test -d "$API_GATEWAY_DIR"; then
        sudo chown -R "root:$GATEWAY_USER" "$API_GATEWAY_DIR"
    else
        echo "⚠️  Warning: API Gateway directory not found: $API_GATEWAY_DIR" >&2
        echo "   Skipping ownership change" >&2
    fi
    
    # Set production permissions
    sudo chmod -R 750 "$API_GATEWAY_DIR/scripts"
    sudo chmod -R 750 "$API_GATEWAY_DIR/config"
    
    # Set permissions separately for directories and files in x-Docs
    find "$API_GATEWAY_DIR/x-Docs" -type d -exec sudo chmod 755 {} \;
    find "$API_GATEWAY_DIR/x-Docs" -type f -exec sudo chmod 644 {} \;
    
    # Ensure config files are readable by service (secure permissions)
    sudo find "$API_GATEWAY_DIR/config" -name "*.yaml" -exec chmod 640 {} \;
    sudo find "$API_GATEWAY_DIR/config" -type d -exec chmod 750 {} \;
    
    echo "✅ Production mode enabled"
    echo "   Files secured with root:$GATEWAY_USER ownership"
    echo "   VS Code editing blocked (production security)"
}

# Main script logic
case "${1:-}" in
    "enable")
        enable_dev_mode
        echo ""
        show_status
        ;;
    "disable")
        disable_dev_mode
        echo ""
        show_status
        ;;
    "status")
        show_status
        ;;
    "help"|"-h"|"--help")
        show_help
        exit 0
        ;;
    *)
        show_help
        exit 1
        ;;
esac
