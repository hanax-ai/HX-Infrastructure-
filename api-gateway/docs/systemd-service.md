# HX Gateway Wrapper - Systemd Service Documentation

## Overview

The HX Gateway Wrapper systemd service (`hx-gateway-ml.service`) provides production-ready lifecycle management for the SOLID-compliant GatewayPipeline. This service integrates seamlessly with existing LiteLLM infrastructure while maintaining independent operation and security isolation.

## Service Architecture

### Port Strategy
```
Port 4010: HX Gateway Wrapper (this service)
Port 4000: LiteLLM Gateway (upstream dependency)
```

### Dependency Chain
```
Network → LiteLLM (4000) → HX Gateway (4010) → Clients
```

### Service Relationships
- **After**: `network-online.target`, `hx-litellm-gateway.service`
- **Wants**: `network-online.target` (graceful network handling)
- **WantedBy**: `multi-user.target` (system-level service)

## SOLID Compliance in Service Design

### Single Responsibility Principle
- **Service Purpose**: Only manages GatewayPipeline lifecycle
- **Clear Boundaries**: No LiteLLM management responsibilities
- **Focused Logging**: Dedicated service logs separate from upstream

### Open/Closed Principle
- **Environment Variables**: Configuration without service modification
- **Plugin Architecture**: Middleware additions don't require service changes
- **Port Configuration**: Configurable endpoints via environment

### Liskov Substitution Principle
- **Standard Interface**: Systemd service contract compliance
- **API Compatibility**: OpenAI-compatible endpoints like LiteLLM
- **Monitoring Integration**: Standard systemd status and logging

### Interface Segregation Principle
- **Minimal Dependencies**: Only essential network and upstream dependencies
- **Security Isolation**: Dedicated user with minimal privileges
- **Resource Limits**: Scoped to wrapper requirements only

### Dependency Inversion Principle
- **Configurable Upstream**: `HX_LITELLM_UPSTREAM` environment variable
- **Abstract Configuration**: YAML-based routing and model registry
- **Environment Abstraction**: No hardcoded deployment assumptions

## Security Configuration

### User Isolation
```bash
# Dedicated system user
User=hx-gateway
Group=hx-gateway

# No shell access, no home directory
useradd --system --no-create-home --shell /bin/false hx-gateway
```

### Security Hardening
```ini
# Prevent privilege escalation
NoNewPrivileges=true

# Isolated temporary directories
PrivateTmp=true

# Protect system directories
ProtectSystem=full

# Isolate from user home directories
ProtectHome=true
```

### Resource Limits
```ini
# File descriptor limits for high concurrency
LimitNOFILE=65536

# Timeout configuration
TimeoutStartSec=30
TimeoutStopSec=30
```

## Environment Configuration

### Secure Environment File Configuration

**Security Best Practice**: Use an EnvironmentFile instead of inline environment variables to protect sensitive credentials.

```ini
# Reference protected environment file
EnvironmentFile=/etc/hx-gateway-ml.env
```

#### Environment File Setup

Create the protected environment file:

```bash
# Create environment file with restricted permissions
sudo tee /etc/hx-gateway-ml.env > /dev/null <<EOF
# Authentication token for API access
MASTER_KEY=your-secure-production-key

# Configurable upstream LiteLLM endpoint  
HX_LITELLM_UPSTREAM=http://127.0.0.1:4000

# Python module resolution
PYTHONPATH=/opt/HX-Infrastructure-/api-gateway/gateway/src
EOF

# Set secure ownership and permissions
sudo chown root:hx-gateway /etc/hx-gateway-ml.env
sudo chmod 640 /etc/hx-gateway-ml.env
```

**Security Notes**:
- File is readable by root and the hx-gateway group only
- Permissions 640 prevent other users from reading sensitive credentials
- Environment variables are loaded securely at service startup

### Configuration File Access
```ini
# Working directory for YAML config access
WorkingDirectory=/opt/HX-Infrastructure-/api-gateway/gateway/src

# Config files located at:
# /opt/HX-Infrastructure-/api-gateway/config/api-gateway/
#   ├── model_registry.yaml
#   └── routing.yaml
```

## Service Lifecycle Management

### Installation and Setup
```bash
# 1. Install dependencies
/opt/HX-Infrastructure-/api-gateway/scripts/setup/install-wrapper-deps.sh

# 2. Install systemd service
sudo /opt/HX-Infrastructure-/api-gateway/scripts/setup/install-systemd-service.sh

# 3. Enable and start service
sudo systemctl enable hx-gateway-ml.service
sudo systemctl start hx-gateway-ml.service
```

### Service Operations
```bash
# Check service status
sudo systemctl status hx-gateway-ml.service

# Start/stop/restart service
sudo systemctl start hx-gateway-ml.service
sudo systemctl stop hx-gateway-ml.service
sudo systemctl restart hx-gateway-ml.service

# Enable/disable automatic startup
sudo systemctl enable hx-gateway-ml.service
sudo systemctl disable hx-gateway-ml.service
```

### Logging and Monitoring
```bash
# View real-time logs
sudo journalctl -u hx-gateway-ml.service -f

# View recent logs
sudo journalctl -u hx-gateway-ml.service --since "1 hour ago"

# View logs with priority
sudo journalctl -u hx-gateway-ml.service -p err

# Export logs for analysis
sudo journalctl -u hx-gateway-ml.service --since today > gateway-logs.txt
```

## Health Monitoring

### Service Health Checks
```bash
# Systemd service status
systemctl is-active hx-gateway-ml.service

# Application health endpoint
curl http://localhost:4010/healthz

# Expected response:
{"status": "ok"}
```

### Performance Monitoring
```bash
# Process information
ps aux | grep uvicorn | grep 4010

# Port verification
netstat -tlnp | grep :4010

# Resource usage
systemctl show hx-gateway-ml.service --property=MemoryCurrent,CPUUsageNSec
```

### Log Analysis
```bash
# Service start events
journalctl -u hx-gateway-ml.service | grep "Started"

# Error patterns
journalctl -u hx-gateway-ml.service | grep -i "error\|exception\|fail"

# Request patterns (if verbose logging enabled)
journalctl -u hx-gateway-ml.service | grep -E "(POST|GET) /v1/"
```

## Configuration Management

### Environment Customization
```bash
# Edit service configuration
sudo systemctl edit hx-gateway-ml.service

# Override environment variables in the EnvironmentFile:
# Edit /etc/hx-gateway-ml.env:
MASTER_KEY=your-production-key
HX_LITELLM_UPSTREAM=http://production-litellm:4000
```

### Routing Configuration
```yaml
# /opt/HX-Infrastructure-/api-gateway/config/api-gateway/routing.yaml
routing:
  strategy: ml-based-routing
  default_group: hx-chat
  failover_order: ["llm02-phi3", "llm01-llama3.2-3b"]

# Changes take effect on service restart
sudo systemctl restart hx-gateway-ml.service
```

### Model Registry Updates
```yaml
# /opt/HX-Infrastructure-/api-gateway/config/api-gateway/model_registry.yaml
models:
  - name: "llm02-phi3"
    tier_score: 0.9
    specializations: ["coding", "analysis"]

# Reload configuration without restart:
# Send SIGHUP to reload configs (if implemented)
sudo systemctl reload hx-gateway-ml.service
```

## Integration with Existing Infrastructure

### LiteLLM Dependency
```ini
# Service starts after LiteLLM is ready
After=hx-litellm-gateway.service

# Graceful handling if LiteLLM is unavailable
# Service will start and log connection errors
# Requests will fail gracefully until upstream is available
```

### Network Configuration
```ini
# Wait for network connectivity
After=network-online.target
Wants=network-online.target

# Service binds to all interfaces on port 4010
ExecStart=... --host 0.0.0.0 --port 4010
```

### Firewall Integration
```bash
# Allow incoming connections on port 4010
sudo ufw allow 4010/tcp

# Verify firewall status
sudo ufw status | grep 4010
```

## Troubleshooting

### Common Issues

#### Service Won't Start
```bash
# Check service status and logs
sudo systemctl status hx-gateway-ml.service
sudo journalctl -u hx-gateway-ml.service --since "10 minutes ago"

# Common causes:
# - Missing virtual environment
# - Permission issues
# - Port already in use
# - Missing configuration files
```

#### Permission Errors
```bash
# Fix ownership
sudo chown -R hx-gateway:hx-gateway /opt/HX-Infrastructure-/api-gateway/gateway/

# Verify permissions
ls -la /opt/HX-Infrastructure-/api-gateway/gateway/
```

#### Port Conflicts
```bash
# Check what's using port 4010
sudo netstat -tlnp | grep :4010
sudo lsof -i :4010

# Kill conflicting processes if needed
sudo pkill -f "port 4010"
```

#### Configuration Errors
```bash
# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('/opt/HX-Infrastructure-/api-gateway/config/api-gateway/routing.yaml'))"

# Check file existence
ls -la /opt/HX-Infrastructure-/api-gateway/config/api-gateway/
```

### Performance Tuning

#### Worker Configuration
```ini
# Increase workers for higher load
ExecStart=... --workers 4

# Monitor worker performance
ps aux | grep uvicorn
```

#### Resource Limits
```ini
# Increase file descriptor limits
LimitNOFILE=131072

# Add memory limits if needed
MemoryLimit=512M
```

## Production Deployment

### Pre-Production Checklist
- [ ] Dependencies installed via `install-wrapper-deps.sh`
- [ ] Service installed via `install-systemd-service.sh`
- [ ] Configuration files validated
- [ ] Health endpoint responding
- [ ] Log rotation configured
- [ ] Monitoring alerts set up
- [ ] Firewall rules configured
- [ ] SSL/TLS termination (if external facing)

### Production Environment Variables

**Use EnvironmentFile for production instead of inline Environment entries:**

```ini
# Use secure environment file
EnvironmentFile=/etc/hx-gateway-ml.env
```

**Example production /etc/hx-gateway-ml.env contents:**
```bash
MASTER_KEY=your-secure-production-key
HX_LITELLM_UPSTREAM=http://internal-litellm:4000
PYTHONPATH=/opt/HX-Infrastructure-/api-gateway/gateway/src
LOG_LEVEL=INFO
```

### Monitoring Integration
```bash
# Prometheus metrics (future enhancement)
# Health check endpoint for load balancers
curl -f http://localhost:4010/healthz || exit 1

# Log aggregation
# Configure log forwarding to central logging system
```

This systemd service configuration provides a robust, secure, and maintainable foundation for the HX Gateway Wrapper while adhering to SOLID principles and production best practices.
