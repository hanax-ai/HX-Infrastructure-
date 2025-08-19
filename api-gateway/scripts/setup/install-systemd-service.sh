#!/bin/bash
# /opt/HX-Infrastructure-/api-gateway/scripts/setup/install-systemd-service.sh
#
# HX Gateway Wrapper - Systemd Service Installation Script
#
# PURPOSE:
#   Creates and configures a production-ready systemd service for the
#   SOLID-compliant GatewayPipeline wrapper on port 4010. This service
#   integrates with the existing LiteLLM infrastructure while providing
#   independent lifecycle management.
#
# ARCHITECTURE INTEGRATION:
#   - Depends on hx-litellm-gateway.service (upstream on port 4000)
#   - Runs on dedicated port 4010 for non-disruptive deployment
#   - Uses isolated virtual environment for dependency management
#   - Implements security hardening following production best practices
#
# SERVICE DESIGN PRINCIPLES:
#   - Single Responsibility: Only manages GatewayPipeline lifecycle
#   - Dependency Inversion: Configurable upstream via environment variables
#   - Open/Closed: Extensible configuration without service modification
#   - Interface Segregation: Minimal privilege principle with security hardening
#
# SECURITY HARDENING:
#   - Dedicated user/group isolation (hx-gateway)
#   - NoNewPrivileges prevents privilege escalation
#   - PrivateTmp provides isolated temporary directories
#   - ProtectSystem=full prevents system modification
#   - ProtectHome isolates from user directories
#
# ENVIRONMENT CONFIGURATION:
#   - HX_MASTER_KEY: Authentication token for API access
#   - HX_LITELLM_UPSTREAM: Configurable upstream LiteLLM endpoint
#   - Working directory in isolated gateway structure
#
# DEPENDENCY MANAGEMENT:
#   - After=network-online.target ensures network availability
#   - After=hx-litellm-gateway.service ensures upstream is ready
#   - Wants=network-online.target for graceful network handling
#
# ERROR HANDLING:
#   - Restart=on-failure for automatic recovery
#   - Systemd integration for logging and monitoring
#   - Clean separation from existing LiteLLM service

set -euo pipefail

# Configuration
SCRIPT_NAME="HX Gateway Wrapper Systemd Service Installation"
SERVICE_NAME="hx-gateway-ml.service"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
LOG_PREFIX="=== [HX GW SYSTEMD]"

echo "$LOG_PREFIX Starting $SCRIPT_NAME ==="

# Validate prerequisites
echo "$LOG_PREFIX Validating prerequisites..."

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo "❌ ERROR: This script must be run as root or with sudo"
    echo "$LOG_PREFIX Usage: sudo $0"
    exit 1
fi

# Check if virtual environment exists
VENV_PATH="/opt/HX-Infrastructure-/api-gateway/gateway/venv"
if [ ! -d "$VENV_PATH" ]; then
    echo "❌ ERROR: Virtual environment not found at $VENV_PATH"
    echo "$LOG_PREFIX Please run install-wrapper-deps.sh first"
    exit 1
fi

# Check if main.py exists
MAIN_PY="/opt/HX-Infrastructure-/api-gateway/gateway/src/main.py"
if [ ! -f "$MAIN_PY" ]; then
    echo "❌ ERROR: Main application file not found at $MAIN_PY"
    echo "$LOG_PREFIX Please ensure the GatewayPipeline implementation is complete"
    exit 1
fi

# User Management
echo "$LOG_PREFIX Configuring service user and group..."
if ! id "hx-gateway" &>/dev/null; then
    echo "$LOG_PREFIX Creating hx-gateway system user..."
    useradd --system --no-create-home --shell /bin/false hx-gateway
else
    echo "$LOG_PREFIX Using existing hx-gateway user"
fi

# Set ownership for gateway directory
echo "$LOG_PREFIX Setting directory ownership..."
chown -R hx-gateway:hx-gateway /opt/HX-Infrastructure-/api-gateway/gateway/

# Create systemd service file
echo "$LOG_PREFIX Creating systemd service file..."
cat > "$SERVICE_PATH" <<'EOF'
# /etc/systemd/system/hx-gateway-ml.service
#
# HX Gateway Wrapper - SOLID-Compliant ML Pipeline Service
#
# This service provides intelligent request routing and middleware processing
# as a non-disruptive wrapper around the existing LiteLLM gateway infrastructure.
#
# ARCHITECTURE:
#   Port 4010: HX Gateway Wrapper (this service)
#   Port 4000: LiteLLM Gateway (upstream dependency)
#
# MIDDLEWARE PIPELINE:
#   Security → Validation → Transform → Routing → Execution
#
# DEPLOYMENT STRATEGY:
#   - Independent lifecycle from LiteLLM
#   - Graceful degradation if upstream unavailable
#   - Configuration-driven routing and model selection
#   - ML-based request optimization

[Unit]
Description=HX Gateway Wrapper (SOLID Pipeline + ML Routing) on :4010
Documentation=file:///opt/HX-Infrastructure-/api-gateway/docs/
After=network-online.target hx-litellm-gateway.service
Wants=network-online.target
# Optional dependency - service will start even if LiteLLM is not available
# This supports testing and development scenarios

[Service]
# Service Identity and Isolation
Type=exec
User=hx-gateway
Group=hx-gateway

# Environment Configuration
# Core authentication token for API access
Environment=HX_MASTER_KEY=sk-hx-dev-1234

# Upstream LiteLLM endpoint - configurable for different environments
Environment=HX_LITELLM_UPSTREAM=http://127.0.0.1:4000

# Python path for proper module resolution
Environment=PYTHONPATH=/opt/HX-Infrastructure-/api-gateway/gateway/src

# Working directory for configuration file access
WorkingDirectory=/opt/HX-Infrastructure-/api-gateway/gateway/src

# Service execution using isolated virtual environment
ExecStart=/opt/HX-Infrastructure-/api-gateway/gateway/venv/bin/uvicorn main:app --host 0.0.0.0 --port 4010 --workers 1

# Lifecycle Management
Restart=on-failure
RestartSec=5
TimeoutStartSec=30
TimeoutStopSec=30

# Resource Limits (adjust based on load requirements)
LimitNOFILE=65536

# Security Hardening
# Prevent privilege escalation attacks
NoNewPrivileges=true

# Provide isolated temporary directories
PrivateTmp=true

# Protect system directories from modification
ProtectSystem=full

# Isolate from user home directories
ProtectHome=true

# Additional hardening options for production
# ProtectKernelTunables=true
# ProtectKernelModules=true
# ProtectControlGroups=true
# RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
EOF

echo "$LOG_PREFIX ✅ Service file created at $SERVICE_PATH"

# Reload systemd configuration
echo "$LOG_PREFIX Reloading systemd daemon..."
systemctl daemon-reload

# Validate service configuration
echo "$LOG_PREFIX Validating service configuration..."
if systemctl cat "$SERVICE_NAME" >/dev/null 2>&1; then
    echo "$LOG_PREFIX ✅ Service configuration validated"
else
    echo "❌ ERROR: Service configuration validation failed"
    exit 1
fi

# Display service status
echo "$LOG_PREFIX Current service status:"
systemctl status "$SERVICE_NAME" --no-pager || true

# Success summary and next steps
echo "$LOG_PREFIX"
echo "$LOG_PREFIX ✅ Systemd service installation completed successfully"
echo "$LOG_PREFIX"
echo "$LOG_PREFIX SERVICE INFORMATION:"
echo "$LOG_PREFIX   Service Name: $SERVICE_NAME"
echo "$LOG_PREFIX   Service File: $SERVICE_PATH"
echo "$LOG_PREFIX   Port: 4010 (HX Gateway Wrapper)"
echo "$LOG_PREFIX   Upstream: http://127.0.0.1:4000 (LiteLLM)"
echo "$LOG_PREFIX   User: hx-gateway"
echo "$LOG_PREFIX   Working Dir: /opt/HX-Infrastructure-/api-gateway/gateway/src"
echo "$LOG_PREFIX"
echo "$LOG_PREFIX NEXT STEPS:"
echo "$LOG_PREFIX   1. Enable service: sudo systemctl enable $SERVICE_NAME"
echo "$LOG_PREFIX   2. Start service:  sudo systemctl start $SERVICE_NAME"
echo "$LOG_PREFIX   3. Check status:   sudo systemctl status $SERVICE_NAME"
echo "$LOG_PREFIX   4. View logs:      sudo journalctl -u $SERVICE_NAME -f"
echo "$LOG_PREFIX   5. Test health:    curl http://localhost:4010/healthz"
echo "$LOG_PREFIX"
echo "$LOG_PREFIX CONFIGURATION:"
echo "$LOG_PREFIX   Environment: Edit $SERVICE_PATH [Service] section"
echo "$LOG_PREFIX   Routing: /opt/HX-Infrastructure-/api-gateway/config/api-gateway/"
echo "$LOG_PREFIX   Models: model_registry.yaml and routing.yaml"
echo "$LOG_PREFIX"
echo "$LOG_PREFIX MONITORING:"
echo "$LOG_PREFIX   Service logs: journalctl -u $SERVICE_NAME"
echo "$LOG_PREFIX   Application logs: Check FastAPI/Uvicorn output"
echo "$LOG_PREFIX   Health endpoint: http://localhost:4010/healthz"
echo "$LOG_PREFIX"
echo "=== [HX GW SYSTEMD] Installation Complete ==="
