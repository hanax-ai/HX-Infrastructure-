#!/usr/bin/env bash
set -euo pipefail

# Error trap for improved diagnostics
trap 'exit_code=$?; echo "ERROR: Script failed at line $LINENO with exit code $exit_code" >&2; echo "Failed command: $BASH_COMMAND" >&2; exit $exit_code' ERR
trap 'exit_code=$?; if [ $exit_code -ne 0 ]; then echo "Script exited with code $exit_code" >&2; fi' EXIT

echo "=== [HX llm-02] GPU Monitoring Setup ==="

# Step 1: Create dedicated system user
echo "[SETUP] Creating dedicated system user..."
if ! id hxmon >/dev/null 2>&1; then
    sudo useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin --comment "HX Monitoring User" hxmon
    echo "✅ Created system user 'hxmon'"
else
    echo "✅ System user 'hxmon' already exists"
fi

# Step 2: Create directory structure
echo "[SETUP] Creating directory structure..."
if [ ! -d /opt/hx/scripts/gpu ]; then 
    sudo mkdir -p /opt/hx/scripts/gpu
    echo "✅ Created /opt/hx/scripts/gpu"
fi

if [ ! -d /opt/hx/logs/gpu ]; then 
    sudo mkdir -p /opt/hx/logs/gpu
    echo "✅ Created /opt/hx/logs/gpu"
fi

# Set ownership for logs directory
sudo chown -R hxmon:hxmon /opt/hx/logs/gpu
echo "✅ Set ownership of /opt/hx/logs/gpu to hxmon:hxmon"

# Step 3: Create nvidia-smi ping script
echo "[SETUP] Creating nvidia-smi ping script..."
sudo tee /opt/hx/scripts/gpu/nvidia_smi_ping.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/opt/hx/logs/gpu"
LOG_FILE="${LOG_DIR}/nvidia-smi-ping.csv"

# Ensure log directory exists with proper permissions
if ! mkdir -p "$LOG_DIR"; then
  echo "ERROR: Failed to create log directory $LOG_DIR" >&2
  exit 1
fi

# Create CSV file with header if missing or empty
if [ ! -s "$LOG_FILE" ]; then
  # Create the file first if it doesn't exist
  if [ ! -f "$LOG_FILE" ]; then
    if ! touch "$LOG_FILE"; then
      echo "ERROR: Failed to create CSV file $LOG_FILE" >&2
      exit 1
    fi
  fi
  
  # Write CSV header with proper error checking
  if ! printf "timestamp,index,name,uuid,pci.bus_id,temperature.gpu,utilization.gpu,memory.used,memory.total\n" >> "$LOG_FILE"; then
    echo "ERROR: Failed to write CSV header to $LOG_FILE" >&2
    exit 1
  fi
fi

trap 'echo "$(date -Is),INFO,stopping nvidia-smi ping" >> "${LOG_DIR}/nvidia-smi-ping.events"; exit 0' INT TERM
trap 'ec=$?; if [ "$ec" -ne 0 ]; then echo "$(date -Is),ERROR,exited unexpectedly (code=$ec)" >> "${LOG_DIR}/nvidia-smi-ping.events"; fi' EXIT

echo "$(date -Is),INFO,starting nvidia-smi ping (10s interval)" >> "${LOG_DIR}/nvidia-smi-ping.events"

while true; do
  TS="$(date -Is)"
  if ! nvidia-smi --query-gpu=index,name,uuid,pci.bus_id,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader \
    | awk -v ts="$TS" -F',' 'BEGIN{OFS=","} {for(i=1;i<=NF;i++){gsub(/^ +| +$/,"",$i)}; print ts,$0}' >> "$LOG_FILE"; then
    echo "$(date -Is),ERROR,nvidia-smi failed" >> "${LOG_DIR}/nvidia-smi-ping.events"
  fi
  sleep 10
done
EOF

# Set permissions
sudo chmod 755 /opt/hx/scripts/gpu/nvidia_smi_ping.sh
echo "✅ Created nvidia_smi_ping.sh script with proper permissions"

# Step 4: Validate script works
echo "[VALIDATION] Testing nvidia-smi ping script..."
echo "Starting background test (12 seconds)..."
timeout 12s sudo -u hxmon /opt/hx/scripts/gpu/nvidia_smi_ping.sh >/dev/null 2>&1 &
validation_pid=$!

# Allow time for the monitor to initialize and start writing data
echo "Waiting for monitor initialization..."
sleep 2

# Check if the process is still running after initialization
if ! kill -0 $validation_pid 2>/dev/null; then
    echo "❌ Monitor process exited during initialization"
    wait $validation_pid 2>/dev/null || true
    exit 1
fi

# Wait for the background process to complete
wait $validation_pid 2>/dev/null || true

echo "[VALIDATION] Checking generated CSV data..."
if [ -f /opt/hx/logs/gpu/nvidia-smi-ping.csv ]; then
    echo "✅ CSV file created successfully"
    echo "Recent entries:"
    tail -n 3 /opt/hx/logs/gpu/nvidia-smi-ping.csv
else
    echo "❌ CSV file not found - check nvidia-smi availability"
    exit 1
fi

# Step 5: Create systemd service
echo "[SETUP] Creating systemd service..."
sudo tee /etc/systemd/system/hx-gpu-ping.service >/dev/null <<'EOF'
[Unit]
Description=HX GPU nvidia-smi ping (10s)
After=network-online.target

[Service]
Type=simple
User=hxmon
Group=hxmon
ExecStartPre=/bin/sh -c 'if ! command -v nvidia-smi >/dev/null 2>&1; then echo "ERROR: nvidia-smi not found in PATH" >&2; exit 1; fi'
ExecStart=/opt/hx/scripts/gpu/nvidia_smi_ping.sh
Restart=always
RestartSec=5
StandardOutput=append:/opt/hx/logs/gpu/hx-gpu-ping.stdout.log
StandardError=append:/opt/hx/logs/gpu/hx-gpu-ping.stderr.log

# Security hardening
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/opt/hx/logs/gpu

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
echo "✅ Created hx-gpu-ping.service and reloaded systemd"

# Step 6: Test service start/stop
echo "[VALIDATION] Testing service start/stop..."
echo "Starting service..."
sudo systemctl start hx-gpu-ping.service && sleep 5
if systemctl is-active --quiet hx-gpu-ping.service; then
    echo "✅ Service started successfully"
else
    echo "❌ Service failed to start"
    sudo systemctl status hx-gpu-ping.service --no-pager --lines=10
    exit 1
fi

echo "Stopping service..."
sudo systemctl stop hx-gpu-ping.service && sleep 5
if ! systemctl is-active --quiet hx-gpu-ping.service; then
    echo "✅ Service stopped successfully"
else
    echo "❌ Service failed to stop"
    exit 1
fi

# Step 7: Final validation
echo "[VALIDATION] Final service status check..."
sudo systemctl status hx-gpu-ping.service --no-pager --lines=5 || true

echo ""
echo "=== GPU Monitoring Setup Complete ==="
echo ""
echo "📋 USAGE COMMANDS:"
echo ""
echo "🚀 Start GPU monitoring:"
echo "  sudo systemctl start hx-gpu-ping.service && sleep 5 && echo 'hx-gpu-ping started successfully!'"
echo ""
echo "🛑 Stop GPU monitoring:"
echo "  sudo systemctl stop hx-gpu-ping.service && sleep 5 && echo 'hx-gpu-ping stopped successfully!'"
echo ""
echo "🔄 Enable at boot (optional):"
echo "  sudo systemctl enable hx-gpu-ping.service && sleep 5 && echo 'hx-gpu-ping enabled to start on boot!'"
echo ""
echo "📊 Monitor live data:"
echo "  watch -n 10 -- 'tail -n 2 /opt/hx/logs/gpu/nvidia-smi-ping.csv'"
echo ""
echo "📈 Check service status:"
echo "  systemctl --no-pager --full status hx-gpu-ping.service"
echo "  tail -n 4 /opt/hx/logs/gpu/nvidia-smi-ping.csv"
echo ""
echo "📁 Log locations:"
echo "  • CSV Data: /opt/hx/logs/gpu/nvidia-smi-ping.csv"
echo "  • Events: /opt/hx/logs/gpu/nvidia-smi-ping.events"
echo "  • Service stdout: /opt/hx/logs/gpu/hx-gpu-ping.stdout.log"
echo "  • Service stderr: /opt/hx/logs/gpu/hx-gpu-ping.stderr.log"
echo ""
echo "✅ Setup completed successfully!"
