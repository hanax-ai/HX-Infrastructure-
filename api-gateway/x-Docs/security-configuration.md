# Security Configuration Guide

## Overview
This guide documents the security hardening implemented for the HX-Infrastructure API Gateway.

## Security Issues Fixed

### 1. Hardcoded Master Key Removal
**Issue**: Configuration files contained hardcoded master keys (`sk-hx-dev-1234`)
**Fix**: Replaced with environment variable references `${MASTER_KEY:?MASTER_KEY environment variable must be set}`
**Files Fixed**:
- `config/api-gateway/config.yaml` 
- `config/api-gateway/config-complete.yaml`

### 2. Hardcoded Bearer Token Removal
**Issue**: Test scripts contained hardcoded authentication tokens
**Fix**: Replaced with configurable `AUTH_TOKEN` environment variable
**Files Fixed**:
- `scripts/tests/smart-fleet-test.sh`

### 3. Division by Zero Protection
**Issue**: Test scripts could divide by zero when calculating success rates
**Fix**: Added conditional check `if [[ $TOTAL_TESTS -gt 0 ]]` before division
**Files Fixed**:
- `scripts/tests/smart-fleet-test.sh`

## Environment Configuration

### Production Setup
1. Copy the environment template:
   ```bash
   sudo cp /opt/HX-Infrastructure-/api-gateway/config/api-gateway/.env.template /opt/HX-Infrastructure-/api-gateway/config/api-gateway/.env
   ```

2. Generate a secure master key:
   ```bash
   openssl rand -hex 32 | sed 's/^/sk-hx-prod-/'
   ```

3. Edit the environment file:
   ```bash
   sudo nano /opt/HX-Infrastructure-/api-gateway/config/api-gateway/.env
   ```

4. Set secure permissions:
   ```bash
   sudo chown hx-gateway:hx-gateway /opt/HX-Infrastructure-/api-gateway/config/api-gateway/.env
   sudo chmod 600 /opt/HX-Infrastructure-/api-gateway/config/api-gateway/.env

### Systemd Environment Configuration

1. Create root-only environment file:
   ```bash
   sudo cp /opt/HX-Infrastructure-/api-gateway/config/api-gateway/systemd.env /etc/hx-litellm-gateway.env
   sudo chown root:root /etc/hx-litellm-gateway.env
   sudo chmod 600 /etc/hx-litellm-gateway.env
   ```

2. Create systemd override directory:
   ```bash
   sudo mkdir -p /etc/systemd/system/hx-litellm-gateway.service.d/
   ```

3. Create proper drop-in override configuration:
   ```bash
   sudo tee /etc/systemd/system/hx-litellm-gateway.service.d/override.conf > /dev/null << 'OVERRIDE'
   [Service]
   EnvironmentFile=/etc/hx-litellm-gateway.env
   
   # Security hardening directives
   User=hx-gateway
   Group=hx-gateway
   NoNewPrivileges=yes
   PrivateTmp=yes
   PrivateDevices=yes
   ProtectSystem=strict
   ProtectHome=yes
   ProtectKernelTunables=yes
   ProtectKernelModules=yes
   ProtectControlGroups=yes
   RestrictSUIDSGID=yes
   RestrictRealtime=yes
   LockPersonality=yes
   MemoryDenyWriteExecute=yes
   
   # Allow write access to specific directories needed by the gateway
   ReadWritePaths=/opt/HX-Infrastructure-/api-gateway/logs
   ReadWritePaths=/tmp
   OVERRIDE
   ```

4. Reload systemd configuration, enable service persistence, and safely restart:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now hx-litellm-gateway.service
   sudo systemctl try-reload-or-restart hx-litellm-gateway.service
   ```

### Testing with Secure Configuration
Set authentication token for testing:
```bash
export AUTH_TOKEN="your-secure-master-key"
./scripts/tests/smart-fleet-test.sh
```

## Security Checklist
- [ ] Remove all hardcoded secrets from repository
- [ ] Generate unique master key for production
- [ ] Set proper file permissions (600) on environment files
- [ ] Use dedicated service user (hx-gateway)
- [ ] Configure systemd environment file
- [ ] Verify no secrets in git history
- [ ] Test authentication with new configuration

## File Permissions
```bash
# Config files - readable by service user only
sudo chown hx-gateway:hx-gateway /opt/HX-Infrastructure-/api-gateway/config/api-gateway/*.yaml
sudo chmod 644 /opt/HX-Infrastructure-/api-gateway/config/api-gateway/*.yaml

# Environment files - restricted access
sudo chown hx-gateway:hx-gateway /opt/HX-Infrastructure-/api-gateway/config/api-gateway/.env
sudo chmod 600 /opt/HX-Infrastructure-/api-gateway/config/api-gateway/.env

# Test scripts - executable
sudo chmod +x /opt/HX-Infrastructure-/api-gateway/scripts/tests/*.sh
```

## Validation
After applying security fixes:
1. Verify no hardcoded secrets in files
2. Test service startup with environment variables
3. Validate authentication with new master key
4. Run test suites with AUTH_TOKEN environment variable
5. Confirm division by zero protection works
