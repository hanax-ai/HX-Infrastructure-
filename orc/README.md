# Server: hx-orc-server
**Primary Role:** Production-Ready Multi-Model Ollama Embedding Platform

## Overview

This server provides a comprehensive, production-ready text embedding platform built on Ollama v0.10.1, following HX-Infrastructure standards. The platform offers three complementary embedding models with complete testing, performance analysis, and external access verification.

## Platform Status: ✅ FULLY OPERATIONAL & EXTERNALLY VERIFIED

- **Service**: Ollama v0.10.1 running on port 11434 (3+ hours uptime)
- **Models**: 3 embedding models (988 MB total)
- **Network**: External access verified (internal network endpoints documented in operations runbook)
- **Security**: Systemd hardening with NoNewPrivileges, ProtectSystem
- **Management**: Complete service lifecycle scripts
- **Testing**: Comprehensive test framework with performance analysis
- **External Access**: Verified from remote clients on network

## Embedding Models Library

| Model | Dimensions | Size | Performance | Verified |
|-------|------------|------|-------------|----------|
| **mxbai-embed-large** | 1024-dim | 669 MB | 74ms latency | ✅ Yes |
| **nomic-embed-text** | 768-dim | 274 MB | 33ms latency | ✅ Yes |
| **all-minilm** | 384-dim | 45 MB | 26ms latency | ✅ Yes |

## Quick Start

### Generate Embeddings

```bash
# Using premium model (1024-dimensional)
curl -X POST http://localhost:11434/api/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model": "mxbai-embed-large", "prompt": "Your text here"}'

# Using high-performance model (768-dimensional)
curl -X POST http://localhost:11434/api/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model": "nomic-embed-text", "prompt": "Your text here"}'

# Using lightweight model (384-dimensional)
curl -X POST http://localhost:11434/api/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model": "all-minilm", "prompt": "Your text here"}'
```

### Service Management

```bash
# Service control scripts
/opt/hx-infrastructure/scripts/service/ollama/start.sh
/opt/hx-infrastructure/scripts/service/ollama/stop.sh
/opt/hx-infrastructure/scripts/service/ollama/restart.sh
/opt/hx-infrastructure/scripts/service/ollama/status.sh

# Comprehensive testing and validation
/opt/hx-infrastructure/scripts/tests/smoke/ollama/smoke.sh
/opt/hx-infrastructure/scripts/tests/smoke/ollama/comprehensive-smoke.sh

# Performance testing framework (Phase 6)
/opt/hx-infrastructure/scripts/tests/perf/embeddings/emb-smoke.sh
/opt/hx-infrastructure/scripts/tests/perf/embeddings/emb-baseline.sh
/opt/hx-infrastructure/scripts/tests/perf/embeddings/analyze_embeddings.py
/opt/hx-infrastructure/scripts/tests/perf/embeddings/run-emb-phase6.sh

# External access verification
/opt/hx-infrastructure/scripts/tests/perf/embeddings/emb-external-test.sh
/opt/hx-infrastructure/scripts/tests/perf/embeddings/emb-external-comprehensive.sh
```

## API Endpoints

- **Version**: `GET /api/version` - Service version information (v0.10.1)
- **Models**: `GET /api/tags` - List available models (3 embedding models)
- **Embeddings**: `POST /api/embeddings` - Generate text embeddings (uses "prompt" parameter)
- **Health**: `GET /` - Root endpoint for connectivity

### API Compatibility Note

The Ollama API uses the `"prompt"` parameter instead of the OpenAI-style `"input"` parameter. Our testing framework includes compatibility validation and fallback handling for client migration scenarios.

## External Access

The embedding platform is network-accessible and verified:

- **Service Verification**: Verified reachable from internal network (endpoints/internal runbook contains exact addresses)
- **Network Interface**: Listening on all interfaces for client access
- **Remote Client Testing**: ✅ Verified from multiple network clients
- **Performance**: All models responding with correct dimensions and stable latency

*For exact internal endpoints and access details, refer to the internal operations runbook.*

## Architecture

### HX-Infrastructure Compliance

```text
/opt/hx-infrastructure/
├── config/ollama/                    # Environment configuration (secured)
├── logs/services/ollama/
│   └── embeddings/                   # Performance logs and baselines
├── reports/perf/embeddings/          # Performance analysis reports
│   ├── emb_perf_summary.csv         # Performance data
│   ├── emb_perf_report.md           # Analysis report
│   ├── latency_ms.png               # Latency charts
│   └── throughput_vectors_per_s.png # Throughput charts
├── scripts/
│   ├── service/ollama/              # Service management (4 scripts)
│   └── tests/
│       ├── smoke/ollama/            # Basic health checks (2 scripts)
│       └── perf/embeddings/         # Advanced testing (8 scripts)
└── models/                          # Model storage (/mnt/active_llm_models)
```

### Security Features

- **Systemd Hardening**: NoNewPrivileges, ProtectSystem, ProtectHome
- **Environment Isolation**: Secure configuration files (640 root:root)
- **Service User**: Dedicated ollama service account
- **Network Security**: Configurable host binding (default: 0.0.0.0:11434)

## Performance Analysis & Testing

### Phase 6 Advanced Testing Framework

The platform includes comprehensive performance testing and analysis:

- **Semantic Coherence**: Validates embedding quality with cosine similarity tests
- **API Compatibility**: Tests parameter handling and fallback scenarios  
- **Performance Baselines**: Collects latency and throughput measurements
- **Statistical Analysis**: Python-based analyzer with matplotlib visualizations
- **External Access**: Verifies remote client connectivity and functionality

### Performance Benchmarks (Latest Results)

| Model | Avg Latency | Throughput | Dimensions | Stability (CoV) |
|-------|-------------|------------|------------|-----------------|
| **mxbai-embed-large** | 61.0ms | 16.7 v/s | 1024 | 14.3% (stable) |
| **nomic-embed-text** | 41.8ms | 24.1 v/s | 768 | 14.2% (stable) |
| **all-minilm** | 33.2ms | 30.8 v/s | 384 | 20.0% (stable) |

*CoV (Coefficient of Variation) ≤ 20% indicates stable performance*

## Model Performance Profiles

### Premium Quality (mxbai-embed-large)

- **Best for**: High-accuracy semantic search, document analysis
- **Dimensions**: 1024 (highest quality)
- **Trade-off**: Larger model size, more compute

### High-Performance (nomic-embed-text)

- **Best for**: Production workloads, balanced quality/speed
- **Dimensions**: 768 (excellent quality)
- **Trade-off**: Good balance of size and performance

### Lightweight/Fast (all-minilm)

- **Best for**: High-throughput, real-time applications
- **Dimensions**: 384 (good quality, very fast)
- **Trade-off**: Compact size, fastest processing

## Deployment History & Phases

- **Phase 1**: Legacy cleanup and baseline preparation ✅
- **Phase 2**: HX-Infrastructure standard deployment ✅
- **Phase 3**: Primary model installation (mxbai-embed-large) ✅
- **Phase 4**: Service management scripts and testing framework ✅
- **Phase 5**: Enhanced model library expansion ✅
- **Phase 6**: Advanced testing, performance analysis, and external verification ✅
  - Task 6.1: Performance testing infrastructure ✅
  - Task 6.2: Comprehensive embedding validation ✅
  - Task 6.3: API compatibility analysis ✅
  - Task 6.4: Performance baseline collection and analysis ✅
  - Task 6.5: External access verification ✅

### Current Status: Production-Ready Multi-Model Platform

All phases complete with comprehensive testing framework and external access verified.

## Support & Documentation

- **Maintainer**: HX-Infrastructure Team
- **Status Tracker**: `x-Docs/deployment-status-tracker.md`
- **API Compatibility**: `x-Docs/api-compatibility-analysis.md`
- **Performance Reports**: `/opt/hx-infrastructure/reports/perf/embeddings/`
- **Repository**: [HX-Infrastructure-](https://github.com/hanax-ai/HX-Infrastructure-)
- **Service Health**: All tests passing, external access verified

---

**Updated:** August 15, 2025 - Phase 6 Complete: Production-Ready Multi-Model Platform with External Verification
