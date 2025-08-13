#!/bin/bash
set -euo pipefail

# Error trap for improved diagnostics
trap 'exit_code=$?; echo "ERROR: Script failed at line $LINENO with exit code $exit_code" >&2; echo "Failed command: $BASH_COMMAND" >&2; exit $exit_code' ERR
trap 'exit_code=$?; if [ $exit_code -ne 0 ]; then echo "Script exited with code $exit_code" >&2; fi' EXIT

echo "=== [HX llm-02] Step 3: Applying Systemd Override ==="

# Create systemd override directory
sudo mkdir -p /etc/systemd/system/ollama.service.d

# Create override configuration
sudo bash -c 'cat > /etc/systemd/system/ollama.service.d/override.conf' <<'EOF'
# [HX-Infrastructure Managed Override]
[Service]
EnvironmentFile=/opt/hx-infrastructure/config/ollama/ollama.env
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
EOF

# Reload systemd configuration
sudo systemctl daemon-reload

# Validation
if systemctl cat ollama | grep -q "/etc/systemd/system/ollama.service.d/override.conf"; then
  echo "Validation successful: Override configuration is loaded."
else
  echo "Validation FAILED: Override configuration not detected." >&2
  exit 1
fi

echo "Systemd override applied successfully."
