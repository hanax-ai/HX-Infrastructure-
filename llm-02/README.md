# LLM-02 Server Infrastructure

**Server**: hx-llm-server-02  
**Hardware**: Dual RTX 5060 Ti GPUs (32GB VRAM)  
**Service**: Ollama v0.11.4 LLM Inference Platform  
**Status**: 🟢 **OPERATIONAL** (Phase 5 Complete)  

---

## Quick Status Overview

| **Component** | **Status** | **Details** |
|---------------|------------|-------------|
| **🖥️ Hardware** | 🟢 **ACTIVE** | 2x RTX 5060 Ti, 3.5TB storage |
| **🔧 Ollama Service** | 🟢 **RUNNING** | v0.11.4, Port 11434 |
| **🔒 Security** | 🟢 **HARDENED** | Systemd restrictions active |
| **📁 Storage** | 🟢 **READY** | /mnt/active_llm_models (3.5TB) |
| **🌐 API** | 🟢 **RESPONDING** | http://0.0.0.0:11434 |
| **⚙️ Service Scripts** | 🟢 **DEPLOYED** | 4 scripts: start/stop/restart/status |

---

## Directory Structure

```
llm-02/
├── README.md                    # This file - server overview
├── backups/                     # Backup storage location
├── config/                      # Configuration files
│   ├── ollama/
│   │   └── ollama.env          # Ollama environment config (local)
│   └── readme/
│       └── template.md.j2      # README template
├── health/                      # Health monitoring
│   └── scripts/
│       └── preflight-check.sh  # System validation script
├── scripts/                     # Operational scripts
│   ├── maintenance/            # Installation & maintenance
│   │   ├── apply-systemd-override.sh
│   │   └── install-ollama.sh   # Ollama installation script
│   ├── service/               # Service management
│   │   └── ollama/            # Ollama-specific scripts
│   └── tests/                 # Testing & validation
│       └── smoke/             # Smoke tests
│           └── ollama/        # Ollama smoke tests
├── services/                   # Service configurations
│   └── metrics/               # Monitoring services
│       └── node-exporter/     # System metrics
└── x-Docs/                    # Documentation
    ├── code-enhancements.md   # Development improvements log
    └── deployment-status-tracker.md  # Detailed deployment status
```

---

## Service Management

### **Quick Commands**

```bash
# Check service status
sudo systemctl status ollama

# Test API endpoint
curl -s http://localhost:11434/api/tags

# Check system resources
./health/scripts/preflight-check.sh

# View recent logs
sudo journalctl -u ollama --no-pager -n 20
```

### **Configuration Locations**

- **System Environment**: `/opt/hx-infrastructure/config/ollama/ollama.env`
- **Service Logs**: `/opt/hx-infrastructure/logs/services/ollama/`
- **Model Storage**: `/mnt/active_llm_models/`
- **Systemd Override**: `/etc/systemd/system/ollama.service.d/override.conf`

---

## Hardware Specifications

### **GPU Configuration**
- **GPU 0**: NVIDIA RTX 5060 Ti (15.3 GiB VRAM)
- **GPU 1**: NVIDIA RTX 5060 Ti (15.3 GiB VRAM)
- **Total Compute**: 32GB VRAM available for inference
- **CUDA Version**: 12.9
- **Driver**: 575.64.03

### **Storage**
- **Model Storage**: 3.5TB dedicated LLM model storage
- **Mount Point**: `/mnt/active_llm_models`
- **Usage**: ~2% (45GB used / 3.6TB total)

---

## Security Configuration

### **Systemd Hardening**
- ✅ **NoNewPrivileges**: Prevents privilege escalation
- ✅ **PrivateTmp**: Isolated temporary directories
- ✅ **ProtectSystem**: File system protection (strict mode)
- ✅ **ProtectHome**: User directory protection

### **Environment Security**
- ✅ **Secure Config File**: `/opt/hx-infrastructure/config/ollama/ollama.env` (640 root:root)
- ✅ **Service User**: Dedicated `ollama` user with minimal privileges
- ✅ **Port Binding**: 0.0.0.0:11434 (external access ready)

---

## Current Deployment Status

### ✅ **COMPLETED PHASES**

1. **Phase 1**: Infrastructure Setup - Directory structure and Git integration
2. **Phase 2**: System Validation - Preflight checks and GPU diagnostics  
3. **Phase 3**: Ollama Installation - Service deployment and GPU integration
4. **Phase 4**: Secure Environment Configuration - Production security hardening
5. **Phase 5**: Service Management Scripts - Standardized operations (start/stop/restart/status)

### 🔄 **NEXT PHASE**

**Phase 6**: Testing & Validation
- Create comprehensive smoke test scripts
- Implement model download and inference testing
- Establish performance baselines and monitoring

---

## Troubleshooting

### **Common Checks**

```bash
# Verify GPU availability
nvidia-smi

# Check service health
sudo systemctl status ollama

# Test API connectivity
timeout 10s curl -s http://localhost:11434/api/tags

# Check disk space
df -h /mnt/active_llm_models

# View error logs
sudo journalctl -u ollama --no-pager -n 50 | grep -i error
```

### **Known Issues**
- **GPU Warning**: CUDA driver initialization warning (non-critical, GPUs still detected)
- **API Latency**: First API call may have higher latency (normal cold start behavior)

---

## Documentation Links

- **📊 Deployment Status**: [deployment-status-tracker.md](x-Docs/deployment-status-tracker.md)
- **🔧 Code Enhancements**: [code-enhancements.md](x-Docs/code-enhancements.md)
- **⚡ Preflight Checks**: [preflight-check.sh](health/scripts/preflight-check.sh)
- **📦 Installation Script**: [install-ollama.sh](scripts/maintenance/install-ollama.sh)

---

## Support & Contact

**Maintainer**: HX-Infrastructure Team  
**Primary Contact**: jarvisr@hana-x.ai  
**Repository**: [HX-Infrastructure](https://github.com/hanax-ai/HX-Infrastructure-)  
**Server Location**: hx-llm-server-02  

---

*Last Updated: August 13, 2025*  
*Infrastructure Version: llm-02 Phase 5*  
*Service Status: Production Ready*
