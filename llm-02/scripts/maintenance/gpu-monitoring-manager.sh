#!/usr/bin/env bash
set -euo pipefail

# GPU Monitoring Service Management Script
SERVICE_NAME="hx-gpu-ping.service"
CSV_FILE="/opt/hx/logs/gpu/nvidia-smi-ping.csv"
EVENTS_FILE="/opt/hx/logs/gpu/nvidia-smi-ping.events"

show_usage() {
    echo "=== [HX llm-02] GPU Monitoring Manager ==="
    echo ""
    echo "USAGE: $0 {start|stop|restart|status|enable|disable|logs|data|watch|compact}"
    echo ""
    echo "COMMANDS:"
    echo "  start     - Start GPU monitoring service"
    echo "  stop      - Stop GPU monitoring service"
    echo "  restart   - Restart GPU monitoring service"
    echo "  status    - Show service status and recent data"
    echo "  enable    - Enable service to start at boot"
    echo "  disable   - Disable service from starting at boot"
    echo "  logs      - Show service logs (stdout/stderr)"
    echo "  data      - Show recent CSV data (last 10 entries)"
    echo "  watch     - Live monitoring of GPU data (Ctrl+C to exit)"
    echo "  compact   - Compact live view (2 lines every 10s, Ctrl+C to exit)"
    echo ""
    echo "FILES:"
    echo "  • CSV Data: $CSV_FILE"
    echo "  • Events: $EVENTS_FILE"
}

check_service_exists() {
    if ! systemctl list-unit-files "${SERVICE_NAME}" >/dev/null 2>&1; then
        echo "❌ Service $SERVICE_NAME not found. Run setup-gpu-monitoring.sh first."
        exit 1
    fi
}

cmd_start() {
    echo "🚀 Starting GPU monitoring service..."
    sudo systemctl start "$SERVICE_NAME" && sleep 5
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "✅ hx-gpu-ping started successfully!"
    else
        echo "❌ Failed to start service"
        sudo systemctl status "$SERVICE_NAME" --no-pager --lines=5
        exit 1
    fi
}

cmd_stop() {
    echo "🛑 Stopping GPU monitoring service..."
    sudo systemctl stop "$SERVICE_NAME" && sleep 5
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "✅ hx-gpu-ping stopped successfully!"
    else
        echo "❌ Failed to stop service"
        exit 1
    fi
}

cmd_restart() {
    echo "🔄 Restarting GPU monitoring service..."
    sudo systemctl restart "$SERVICE_NAME" && sleep 5
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "✅ hx-gpu-ping restarted successfully!"
    else
        echo "❌ Failed to restart service"
        sudo systemctl status "$SERVICE_NAME" --no-pager --lines=5
        exit 1
    fi
}

cmd_status() {
    echo "📊 GPU Monitoring Service Status:"
    echo ""
    sudo systemctl status "$SERVICE_NAME" --no-pager --lines=8
    echo ""
    
    if [ -f "$CSV_FILE" ]; then
        echo "📈 Recent GPU Data (last 4 entries):"
        tail -n 4 "$CSV_FILE"
        echo ""
        
        # Show data freshness
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            last_entry=$(tail -n 1 "$CSV_FILE" | cut -d',' -f1)
            current_time=$(date -Is)
            echo "🕐 Last data entry: $last_entry"
            echo "🕐 Current time: $current_time"
            
            # Calculate data age if last_entry is non-empty
            if [ -n "$last_entry" ]; then
                data_age=""
                
                # Use Python for robust ISO8601 timestamp parsing
                if command -v python3 >/dev/null 2>&1; then
                    data_age=$(python3 -c "
import sys
from datetime import datetime
import re

def calculate_age(timestamp):
    try:
        # Parse ISO8601 timestamp with timezone support
        # Handle various formats: 2025-08-14T00:52:41+00:00, 2025-08-14T00:52:41Z, etc.
        timestamp = timestamp.strip()
        
        # Normalize Z to +00:00
        if timestamp.endswith('Z'):
            timestamp = timestamp[:-1] + '+00:00'
        
        # Parse with timezone awareness
        dt = datetime.fromisoformat(timestamp)
        
        # Convert to UTC epoch
        epoch_seconds = int(dt.timestamp())
        
        # Get current UTC epoch
        current_epoch = int(datetime.now().timestamp())
        
        # Calculate age
        age = current_epoch - epoch_seconds
        
        # Validate: must be non-negative and within 1 year
        if age < 0 or age > 365*24*3600:
            return ''
        
        return str(age)
    except Exception:
        return ''

result = calculate_age('$last_entry')
print(result)
" 2>/dev/null) || data_age=""
                elif command -v python >/dev/null 2>&1; then
                    # Fallback to python2 if available (less reliable but better than nothing)
                    data_age=$(python -c "
import sys
import time
import re
from datetime import datetime

def calculate_age(timestamp):
    try:
        timestamp = timestamp.strip()
        
        # Basic ISO8601 parsing for python2 (limited timezone support)
        if timestamp.endswith('Z'):
            timestamp = timestamp[:-1]
        elif '+' in timestamp[-6:] or '-' in timestamp[-6:]:
            timestamp = timestamp[:-6]  # Strip timezone for python2
        
        # Parse basic format
        dt = datetime.strptime(timestamp[:19], '%Y-%m-%dT%H:%M:%S')
        epoch_seconds = int(time.mktime(dt.timetuple()))
        
        current_epoch = int(time.time())
        age = current_epoch - epoch_seconds
        
        if age < 0 or age > 365*24*3600:
            return ''
        
        return str(age)
    except Exception:
        return ''

result = calculate_age('$last_entry')
print(result)
" 2>/dev/null) || data_age=""
                fi
                
                # Display data age if successfully calculated and valid
                if [ -n "$data_age" ] && echo "$data_age" | grep -q '^[0-9]\+$'; then
                    echo "⏱️  Data age: ${data_age}s"
                fi
            fi
        fi
    else
        echo "📈 No CSV data file found yet"
    fi
}

cmd_enable() {
    echo "🔄 Enabling GPU monitoring to start at boot..."
    sudo systemctl enable "$SERVICE_NAME" && sleep 5
    echo "✅ hx-gpu-ping enabled to start on boot!"
}

cmd_disable() {
    echo "🔄 Disabling GPU monitoring from starting at boot..."
    sudo systemctl disable "$SERVICE_NAME" && sleep 5
    echo "✅ hx-gpu-ping disabled from starting on boot!"
}

cmd_logs() {
    echo "📋 GPU Monitoring Service Logs:"
    echo ""
    echo "=== Recent Events ==="
    if [ -f "$EVENTS_FILE" ]; then
        tail -n 10 "$EVENTS_FILE"
    else
        echo "No events file found"
    fi
    
    echo ""
    echo "=== Service Journal (last 20 lines) ==="
    sudo journalctl -u "$SERVICE_NAME" --no-pager -n 20
}

cmd_data() {
    echo "📊 Recent GPU Monitoring Data:"
    echo ""
    if [ -f "$CSV_FILE" ]; then
        echo "=== CSV Header ==="
        head -n 1 "$CSV_FILE"
        echo ""
        echo "=== Last 10 Entries ==="
        tail -n 10 "$CSV_FILE"
        echo ""
        echo "=== File Stats ==="
        echo "Total entries: $(wc -l < "$CSV_FILE")"
        echo "File size: $(du -h "$CSV_FILE" | cut -f1)"
    else
        echo "❌ No CSV data file found at $CSV_FILE"
    fi
}

cmd_watch() {
    echo "👀 Live GPU Monitoring (refreshes every 10 seconds)"
    echo "Press Ctrl+C to stop watching"
    echo ""
    
    if [ ! -f "$CSV_FILE" ]; then
        echo "❌ No CSV data file found at $CSV_FILE"
        exit 1
    fi
    
    # Check if watch utility is available
    if command -v watch >/dev/null 2>&1; then
        # Use watch utility if available
        watch -n 10 -- "echo '=== Live GPU Data ===' && tail -n 3 '$CSV_FILE' && echo '' && echo 'Last updated: \$(date)'"
    else
        # Portable fallback loop for minimal environments
        echo "watch utility not found, using portable fallback"
        echo ""
        
        # Set up trap for clean exit on Ctrl+C
        trap 'echo ""; echo "Monitoring stopped."; exit 0' INT TERM
        
        while true; do
            # Clear screen if tput is available, otherwise just add some spacing
            if command -v tput >/dev/null 2>&1; then
                tput clear
            else
                printf "\n\n\n"
            fi
            
            echo "=== Live GPU Data ==="
            if [ -f "$CSV_FILE" ]; then
                tail -n 3 "$CSV_FILE"
            else
                echo "CSV file not found"
            fi
            echo ""
            echo "Last updated: $(date)"
            echo ""
            echo "Press Ctrl+C to stop watching..."
            
            sleep 10
        done
    fi
}

cmd_compact() {
    echo "📊 Compact GPU Monitoring View (refreshes every 10 seconds)"
    echo "Press Ctrl+C to stop watching"
    echo ""
    
    if [ ! -f "$CSV_FILE" ]; then
        echo "❌ No CSV data file found at $CSV_FILE"
        exit 1
    fi
    
    # Check if watch utility is available
    if command -v watch >/dev/null 2>&1; then
        # Use the exact command specified in the original requirements
        watch -n 10 -- "tail -n 2 '$CSV_FILE'"
    else
        # Portable fallback loop for minimal environments
        echo "watch utility not found, using portable fallback"
        echo ""
        
        # Set up trap for clean exit on Ctrl+C
        trap 'echo ""; echo "Compact monitoring stopped."; exit 0' INT TERM
        
        while true; do
            # Clear screen if tput is available
            if command -v tput >/dev/null 2>&1; then
                tput clear
            else
                printf "\n\n"
            fi
            
            echo "=== Compact GPU Data ==="
            if [ -f "$CSV_FILE" ]; then
                tail -n 2 "$CSV_FILE"
            else
                echo "CSV file not found"
            fi
            echo ""
            echo "Updated: $(date)"
            echo "Press Ctrl+C to stop..."
            
            sleep 10
        done
    fi
}

# Main execution
case "${1:-}" in
    start)
        check_service_exists
        cmd_start
        ;;
    stop)
        check_service_exists
        cmd_stop
        ;;
    restart)
        check_service_exists
        cmd_restart
        ;;
    status)
        check_service_exists
        cmd_status
        ;;
    enable)
        check_service_exists
        cmd_enable
        ;;
    disable)
        check_service_exists
        cmd_disable
        ;;
    logs)
        check_service_exists
        cmd_logs
        ;;
    data)
        cmd_data
        ;;
    watch)
        cmd_watch
        ;;
    compact)
        cmd_compact
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
