# LLM-01 Server Infrastructure

**Server**: hx-llm-server-01  
**Hardware**: Dual RTX 4070 Ti GPUs (32GB VRAM)  
**Service**: Ollama v0.11.4 LLM Inference Platform  
**Status**: 🟢 **OPERATIONAL** (Architecture Aligned)  

---

## 🎯 Architecture Alignment Complete

✅ **ALIGNED WITH LLM-02**: llm-01 successfully standardized to canonical `/mnt/active_llm_models` path

| **Component** | **Status** | **Details** |
|---------------|------------|-------------|
| **🖥️ Hardware** | 🟢 **ACTIVE** | 2x RTX 4070 Ti, 7.3TB storage |
| **🔧 Ollama Service** | 🟢 **RUNNING** | v0.11.4, Port 11434 |
| **🔒 Security** | 🟢 **HARDENED** | Least-privilege implemented |
| **📁 Storage** | 🟢 **ALIGNED** | Canonical `/mnt/active_llm_models` ✅ |
| **🌐 API** | 🟢 **RESPONDING** | http://0.0.0.0:11434 |
| **⚙️ Service Scripts** | 🟢 **STANDARDIZED** | Global shared scripts active |
| **🤖 Models** | 🟢 **PRESERVED** | All 3 production models (18.4GB) |

---

## Storage Mapping (POST-ALIGNMENT)

**NEW: Canonical Architecture**
- **Canonical Path**: `/mnt/active_llm_models` (standardized with llm-02)
- **Real Storage**: `/data/llm_bulk_storage` (7.3TB)
- **Compatibility**: `/opt/hx-infrastructure/llm-01/models/production` → `/mnt/active_llm_models`
- **Migration**: ✅ 18.5GB models migrated with zero data loss

**Legacy Mapping (PRE-ALIGNMENT)**
- ~~NVMe Device: /dev/nvme1n1p1~~ (not in use)
- ~~SATA Device: /dev/sda1~~ (now mounted at canonical location)
- ~~Models Mount: /opt/hx-infrastructure/llm-01/models~~ (now symlinked)
- ~~Bulk Storage Mount: /opt/hx-infrastructure/llm-01/data/llm_bulk_storage~~ (now symlinked)

---

## Model Registry (Current Production)

**✅ User-Preferred Models (Preserved Through Alignment)**:
```bash
# Model inventory maintained during architecture alignment
NAME                       ID              SIZE      MODIFIED   
llama3.2:3b                a80c4f17acd5    2.0 GB    2 days ago    
qwen3:1.7b                 8f68893c685c    1.4 GB    2 days ago    
mistral-small3.2:latest    5a408ab55df5    15 GB     2 days ago
```

**Configuration** (`/opt/hx-infrastructure/llm-01/config/ollama/ollama.env`):
```bash
OLLAMA_MODELS="/mnt/active_llm_models"                         # ✅ Canonical path
OLLAMA_MODEL_LLAMA32="llama3.2:3b"
OLLAMA_MODEL_QWEN3="qwen3:1.7b"  
OLLAMA_MODEL_MISTRAL="mistral-small3.2@sha256:5a408ab55df5"
OLLAMA_MODELS_AVAILABLE="llama3.2:3b,qwen3:1.7b,mistral-small3.2@sha256:5a408ab55df5"
```

---

## Services & Monitoring

**Enhanced Service Management**:
- **Global Scripts**: ✅ Standardized service management via `/opt/scripts/service/ollama/`
- **Local Fallback**: ✅ Symlinks from local paths for compatibility
- **Validation**: ✅ Enhanced configuration validation with `validate-model-config.sh`

**Active Monitoring**:
- **GPU Telemetry**: ✅ Every 5 minutes → `/llm-01/logs/gpu/nvidia-smi-ping.csv`
- **Nightly Smoke Tests**: ✅ Daily at 00:03 UTC → `/opt/hx-infrastructure/logs/services/ollama/perf/nightly-smoke.log`
- **Performance Baseline**: Current first-token latencies:
  - `llama3.2:3b`: 1.64s (fastest)
  - `qwen3:1.7b`: 1.98s  
  - `mistral-small3.2:latest`: 5.44s (largest)

**Service Status**:
- Ollama: ✅ active and responding
- Node Exporter: ✅ `/opt/hx-infrastructure/llm-01/services/metrics/node-exporter`
- GPU Telemetry: ✅ Automated collection active
- Security Audit: ✅ Zero vulnerabilities (hardened)

---

## Architecture Benefits

### **✅ Standardization Achieved**
- **Cross-Node Consistency**: Both llm-01 and llm-02 use identical canonical paths
- **Simplified Operations**: Global service scripts eliminate node-specific variations
- **Unified Storage**: Consistent `/mnt/active_llm_models` across infrastructure

### **✅ Backward Compatibility**
- **Existing Automation**: Continues to work via compatibility symlinks
- **Zero Breaking Changes**: All existing scripts and references preserved
- **Gradual Migration**: Old paths redirect seamlessly to new architecture

### **✅ Enhanced Capabilities**
- **Validation Framework**: Comprehensive model configuration validation
- **Shared Libraries**: Reusable parsing functions in `/lib/model-config.sh`
- **Production Monitoring**: Automated GPU telemetry and nightly validation

---

## Validation Summary

**✅ Last Health Check**: August 14, 2025
- **Hardware**: 2x RTX 4070 Ti operational, CUDA 12.9 ready
- **Service**: Ollama v0.11.4 active on port 11434
- **Models**: All 3 production models accessible and responding
- **Storage**: 7.3TB canonical storage accessible, models at `/mnt/active_llm_models`

**✅ Enhanced Validation Scripts**:
```bash
# Comprehensive model validation
./validate-model-config.sh /opt/hx-infrastructure/llm-01/config/ollama/ollama.env strict
# Result: ✅ All checks pass, 3 models validated

# Model reference extraction testing  
./test-extraction.sh /opt/hx-infrastructure/llm-01/config/ollama/ollama.env
# Result: ✅ All model references extracted correctly

# External connectivity verification (NEW) ✨
./emb-external-verify.sh 192.168.10.30 11434
# Result: ✅ External access validation with latency/semantic testing
```

**✅ Smoke Tests**: 
- **Global Scripts**: `/opt/scripts/tests/smoke/ollama/smoke.sh` → ✅ PASS
- **API Functionality**: All 3 models responding correctly
- **Concurrency**: 4 concurrent requests successful

---

*Generated on August 15, 2025*  
*Architecture Status: ✅ **ALIGNED WITH LLM-02 CANONICAL PATHS***  
*Infrastructure Version: llm-01 Post-Alignment with External Verification*  
*Next Review: Ongoing production monitoring*
