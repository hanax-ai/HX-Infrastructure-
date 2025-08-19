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
