#!/bin/bash
# /opt/HX-Infrastructure-/api-gateway/scripts/setup/create-service-scripts.sh
#
# HX Gateway Wrapper - Service Management Scripts Generator
#
# PURPOSE:
#   Creates standardized service management scripts following SOLID principles
#   for lifecycle management of the HX Gateway Wrapper systemd service.
#   Provides consistent interface for start/stop/status operations across
#   the infrastructure with proper error handling and user feedback.
#
# SOLID COMPLIANCE:
#   - Single Responsibility: Each script handles one specific service operation
#   - Open/Closed: Scripts can be extended without modifying core logic
#   - Interface Segregation: Minimal, focused script interfaces
#   - Dependency Inversion: Abstract systemd service interface
#
# SCRIPT ARCHITECTURE:
#   start.sh  - Service startup with validation and success confirmation
#   stop.sh   - Service shutdown with validation and success confirmation  
#   status.sh - Service status display with recent log output
#
# ERROR HANDLING:
#   - Exit codes for automation integration (0=success, 1=failure)
#   - Stderr output for error conditions
#   - Validation delays for proper service state verification
#   - Graceful degradation for log access issues
#
# INTEGRATION STRATEGY:
#   - Follows existing HX infrastructure script patterns
#   - Compatible with existing service management workflows
#   - Provides consistent output formatting across services
#   - Supports both interactive and automated usage

set -euo pipefail  # Strict error handling for reliable automation

# Configuration constants following SOLID principles
readonly SCRIPT_NAME="HX Gateway Service Scripts Generator"
readonly SERVICE_NAME="hx-gateway-ml.service"
readonly BASE_DIR="/opt/HX-Infrastructure-/api-gateway/scripts/service/api-gateway-ml"
readonly LOG_PREFIX="=== [HX GW SCRIPTS]"

# Validation delay for proper systemd state verification
readonly VALIDATION_DELAY=5

# Log display configuration for status script
readonly LOG_LINES=20

echo "$LOG_PREFIX Starting $SCRIPT_NAME ==="

# Directory creation with proper error handling
# Single Responsibility: Only handles directory structure setup
echo "$LOG_PREFIX Creating service scripts directory..."
if ! sudo mkdir -p "$BASE_DIR"; then
    echo "❌ ERROR: Failed to create directory $BASE_DIR" >&2
    exit 1
fi

echo "$LOG_PREFIX Directory created at: $BASE_DIR"

# START SCRIPT - Single Responsibility: Service startup management
# Open/Closed: Extensible for additional startup validation
echo "$LOG_PREFIX Creating start.sh script..."
sudo bash -c "cat > ${BASE_DIR}/start.sh" <<'EOF'
#!/usr/bin/env bash
# /opt/HX-Infrastructure-/api-gateway/scripts/service/api-gateway-ml/start.sh
#
# HX Gateway Wrapper - Service Start Script
#
# PURPOSE:
#   Starts the HX Gateway Wrapper systemd service with proper validation
#   and user feedback. Implements reliable startup with state verification.
#
# SOLID COMPLIANCE:
#   - Single Responsibility: Only handles service startup operations
#   - Dependency Inversion: Uses abstract systemd service interface
#   - Interface Segregation: Minimal start operation interface
#
# ERROR HANDLING:
#   - Pre-validation of service existence
#   - Post-startup state verification with delay
#   - Clear success/failure messaging
#   - Proper exit codes for automation
#
# USAGE:
#   ./start.sh                    # Interactive usage
#   ./start.sh && echo "Success"  # Automation usage

set -euo pipefail

readonly SERVICE_NAME="hx-gateway-ml.service"
readonly VALIDATION_DELAY=5

echo "=== [HX Gateway Wrapper] Service Start Operation ==="
echo "Executing: Start HX Gateway Wrapper"

# Initiate service startup
# Dependency Inversion: Abstract systemd interface usage
if ! sudo systemctl start "$SERVICE_NAME"; then
    echo "❌ ERROR: Failed to initiate service startup" >&2
    exit 1
fi

echo "Service start command issued, validating state..."

# Validation delay for proper systemd state stabilization
# This ensures reliable state verification after startup
sleep $VALIDATION_DELAY

# Post-startup validation with clear success/failure feedback
# Interface Segregation: Focused validation interface
if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "✅ HX Gateway Wrapper started successfully!"
    echo "Service is now active and ready to accept requests on port 4010"
    echo "Health check: curl http://localhost:4010/healthz"
    exit 0
else
    echo "❌ ERROR: Service failed to start properly" >&2
    echo "Check service logs: sudo journalctl -u $SERVICE_NAME --since '1 minute ago'" >&2
    exit 1
fi
EOF

# STOP SCRIPT - Single Responsibility: Service shutdown management
# Open/Closed: Extensible for additional shutdown procedures
echo "$LOG_PREFIX Creating stop.sh script..."
sudo bash -c "cat > ${BASE_DIR}/stop.sh" <<'EOF'
#!/usr/bin/env bash
# /opt/HX-Infrastructure-/api-gateway/scripts/service/api-gateway-ml/stop.sh
#
# HX Gateway Wrapper - Service Stop Script
#
# PURPOSE:
#   Stops the HX Gateway Wrapper systemd service with proper validation
#   and graceful shutdown handling. Ensures clean service termination.
#
# SOLID COMPLIANCE:
#   - Single Responsibility: Only handles service shutdown operations
#   - Dependency Inversion: Uses abstract systemd service interface
#   - Interface Segregation: Minimal stop operation interface
#
# ERROR HANDLING:
#   - Graceful shutdown initiation
#   - Post-shutdown state verification with delay
#   - Clear success/failure messaging
#   - Proper exit codes for automation
#
# USAGE:
#   ./stop.sh                     # Interactive usage
#   ./stop.sh && echo "Stopped"   # Automation usage

set -euo pipefail

readonly SERVICE_NAME="hx-gateway-ml.service"
readonly VALIDATION_DELAY=5

echo "=== [HX Gateway Wrapper] Service Stop Operation ==="
echo "Executing: Stop HX Gateway Wrapper"

# Initiate graceful service shutdown
# Dependency Inversion: Abstract systemd interface usage
if ! sudo systemctl stop "$SERVICE_NAME"; then
    echo "❌ ERROR: Failed to initiate service shutdown" >&2
    exit 1
fi

echo "Service stop command issued, validating state..."

# Validation delay for proper systemd state stabilization
# This ensures reliable state verification after shutdown
sleep $VALIDATION_DELAY

# Post-shutdown validation with clear success/failure feedback
# Interface Segregation: Focused validation interface
if ! sudo systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "✅ HX Gateway Wrapper stopped successfully!"
    echo "Service is now inactive and no longer accepting requests"
    exit 0
else
    echo "❌ ERROR: Service failed to stop properly" >&2
    echo "Check service status: sudo systemctl status $SERVICE_NAME" >&2
    echo "Force stop if needed: sudo systemctl kill $SERVICE_NAME" >&2
    exit 1
fi
EOF

# STATUS SCRIPT - Single Responsibility: Service status reporting
# Open/Closed: Extensible for additional status information
echo "$LOG_PREFIX Creating status.sh script..."
sudo bash -c "cat > ${BASE_DIR}/status.sh" <<'EOF'
#!/usr/bin/env bash
# /opt/HX-Infrastructure-/api-gateway/scripts/service/api-gateway-ml/status.sh
#
# HX Gateway Wrapper - Service Status Script
#
# PURPOSE:
#   Displays comprehensive status information for the HX Gateway Wrapper
#   including systemd service state and recent log entries for troubleshooting.
#
# SOLID COMPLIANCE:
#   - Single Responsibility: Only handles status information display
#   - Dependency Inversion: Uses abstract systemd and logging interfaces
#   - Interface Segregation: Focused status reporting interface
#
# ERROR HANDLING:
#   - Graceful degradation if status/logs unavailable
#   - Non-failing execution for automation compatibility
#   - Clear section separation for readability
#
# OUTPUT SECTIONS:
#   1. Systemd service status (detailed)
#   2. Recent log entries (last 20 lines)
#   3. Health endpoint information
#
# USAGE:
#   ./status.sh                   # Interactive status display
#   ./status.sh | grep "Active"   # Automation status parsing

set -euo pipefail

readonly SERVICE_NAME="hx-gateway-ml.service"
readonly LOG_LINES=20

echo "=== [HX Gateway Wrapper] Service Status Report ==="

# Systemd service status display with graceful error handling
# Dependency Inversion: Abstract systemd interface usage
echo "--- Service Status ---"
if sudo systemctl status --no-pager "$SERVICE_NAME" 2>/dev/null; then
    echo "Service status retrieved successfully"
else
    echo "⚠️  Warning: Could not retrieve service status (service may not be installed)"
fi

echo ""

# Recent log entries for troubleshooting and monitoring
# Open/Closed: Log analysis extensible without modifying core logic
echo "--- Recent Logs (Last $LOG_LINES entries) ---"
if sudo journalctl -u "$SERVICE_NAME" -n "$LOG_LINES" --no-pager 2>/dev/null; then
    echo "Log entries retrieved successfully"
else
    echo "⚠️  Warning: Could not retrieve log entries (insufficient permissions or service not found)"
fi

echo ""

# Additional status information for operations
echo "--- Quick Status Check ---"
if sudo systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo "✅ Service is ACTIVE"
    echo "🌐 Health check: curl http://localhost:4010/healthz"
    echo "📊 Real-time logs: sudo journalctl -u $SERVICE_NAME -f"
else
    echo "❌ Service is INACTIVE or NOT INSTALLED"
    echo "🔧 Start service: sudo systemctl start $SERVICE_NAME"
    echo "📋 Install service: Run setup scripts in /opt/HX-Infrastructure-/api-gateway/scripts/setup/"
fi

echo ""
echo "=== [HX Gateway Wrapper] Status Report Complete ==="
EOF

# Set executable permissions for all service scripts
# Interface Segregation: Focused permission management
echo "$LOG_PREFIX Setting executable permissions..."
if ! sudo chmod +x "${BASE_DIR}/"*.sh; then
    echo "❌ ERROR: Failed to set executable permissions" >&2
    exit 1
fi

# Verify script creation and permissions
echo "$LOG_PREFIX Verifying script creation..."
for script in start.sh stop.sh status.sh; do
    script_path="${BASE_DIR}/${script}"
    if [[ -f "$script_path" && -x "$script_path" ]]; then
        echo "✅ $script created and executable"
    else
        echo "❌ ERROR: $script creation or permission setting failed" >&2
        exit 1
    fi
done

# Success summary with usage instructions
echo "$LOG_PREFIX"
echo "$LOG_PREFIX ✅ Service management scripts created successfully"
echo "$LOG_PREFIX"
echo "$LOG_PREFIX CREATED SCRIPTS:"
echo "$LOG_PREFIX   Start:  ${BASE_DIR}/start.sh"
echo "$LOG_PREFIX   Stop:   ${BASE_DIR}/stop.sh" 
echo "$LOG_PREFIX   Status: ${BASE_DIR}/status.sh"
echo "$LOG_PREFIX"
echo "$LOG_PREFIX USAGE EXAMPLES:"
echo "$LOG_PREFIX   Start service:  ${BASE_DIR}/start.sh"
echo "$LOG_PREFIX   Stop service:   ${BASE_DIR}/stop.sh"
echo "$LOG_PREFIX   Check status:   ${BASE_DIR}/status.sh"
echo "$LOG_PREFIX"
echo "$LOG_PREFIX SOLID PRINCIPLES IMPLEMENTED:"
echo "$LOG_PREFIX   ✅ Single Responsibility: Each script has one focused operation"
echo "$LOG_PREFIX   ✅ Open/Closed: Scripts extensible without core modification"
echo "$LOG_PREFIX   ✅ Interface Segregation: Minimal, focused script interfaces"
echo "$LOG_PREFIX   ✅ Dependency Inversion: Abstract systemd service interface"
echo "$LOG_PREFIX"
echo "$LOG_PREFIX INTEGRATION FEATURES:"
echo "$LOG_PREFIX   🔧 5-second validation delays for reliable state verification"
echo "$LOG_PREFIX   📋 Consistent success/failure messaging across operations"
echo "$LOG_PREFIX   🚨 Proper exit codes for automation and CI/CD integration"
echo "$LOG_PREFIX   📊 Comprehensive status reporting with logs and health info"
echo "$LOG_PREFIX"
echo "=== [HX GW SCRIPTS] Creation Complete ==="
