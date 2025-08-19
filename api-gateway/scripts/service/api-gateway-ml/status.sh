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
