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
