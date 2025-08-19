#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY configures file/directory permissions
echo "=== [Permissions Manager] Setting Proper Ownership & Permissions ==="

BASE="/opt/HX-Infrastructure-/api-gateway"
TEST_DIR="${BASE}/scripts/tests/gateway"
LOG_DIR="${BASE}/logs/services/gateway"

# Preflight check
if [[ ! -d "$TEST_DIR" ]]; then
    echo "❌ Test directory not found: $TEST_DIR"
    exit 1
fi

# Check if hx-gateway user exists
if ! id hx-gateway >/dev/null 2>&1; then
    echo "❌ hx-gateway user not found"
    echo "   Please run the gateway deployment script first"
    exit 1
fi

echo "→ Setting ownership to hx-gateway user..."
# Ensure directories exist before setting ownership
mkdir -p "$LOG_DIR"
mkdir -p "$TEST_DIR"
sudo chown -R hx-gateway:hx-gateway "$TEST_DIR" "$LOG_DIR"

echo "→ Setting directory permissions (755)..."
sudo find "$TEST_DIR" -type d -exec sudo chmod 755 {} \;

echo "→ Setting script permissions (755 for executables, excluding config dir)..."
sudo find "$TEST_DIR" -type f -name "*.sh" -not -path "$TEST_DIR/config/*" -exec sudo chmod 755 {} \;

echo "→ Setting config file permissions (644)..."
sudo find "$TEST_DIR/config" -type f -name "*.sh" -exec sudo chmod 644 {} \; 2>/dev/null || true
sudo find "$TEST_DIR/config" -type f ! -name "*.sh" -exec sudo chmod 644 {} \; 2>/dev/null || true

echo "→ Setting log directory permissions..."
sudo chmod 755 "$LOG_DIR"

echo "✅ Permissions configured successfully"
echo "Owner: hx-gateway:hx-gateway"
echo "Directories: 755, Scripts: 755, Configs: 644"
