# HX Infrastructure API Gateway Configuration

## Overview

This directory contains the configuration files for the HX Infrastructure API Gateway. The gateway acts as a unified interface to multiple LLM nodes and embedding services across the infrastructure.

## Environment Variables

The configuration files use environment variable substitution for portability across different deployment environments. The following environment variables are required or recommended:

### Required Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `HX_MASTER_KEY` | Authentication master key for the gateway | **(required)** | `sk-hx-prod-abc123...` |

### Host Configuration Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `ORC_HOST` | IP address for orchestrator node (embeddings) | `192.168.10.31` | `192.168.10.31` |
| `LLM01_HOST` | IP address for LLM-01 node (small/fast models) | `192.168.10.29` | `192.168.10.29` |
| `LLM02_HOST` | IP address for LLM-02 node (large/specialized models) | `192.168.10.28` | `192.168.10.28` |
| `OLLAMA_PORT` | Port for Ollama services across all nodes | `11434` | `11434` |

## Configuration Setup

### Development Environment

```bash
# Set required authentication
export HX_MASTER_KEY="sk-hx-dev-your-secure-key"

# Use default IP addresses (no additional exports needed)
# ORC_HOST=192.168.10.31
# LLM01_HOST=192.168.10.29  
# LLM02_HOST=192.168.10.28
# OLLAMA_PORT=11434
```

### Production Environment

```bash
# Set required authentication
export HX_MASTER_KEY="sk-hx-prod-your-production-key"

# Override host addresses for production deployment
export ORC_HOST="10.0.1.31"
export LLM01_HOST="10.0.1.29"
export LLM02_HOST="10.0.1.28"
export OLLAMA_PORT="11434"
```

### Docker/Container Environment

```bash
# Set required authentication
export HX_MASTER_KEY="sk-hx-container-key"

# Use service discovery names
export ORC_HOST="orc-service"
export LLM01_HOST="llm01-service"
export LLM02_HOST="llm02-service"
export OLLAMA_PORT="11434"
```

## Node Architecture

### ORC Node (`${ORC_HOST}`)
- **Purpose**: Embedding services
- **Models**: 
  - `mxbai-embed-large` (premium embeddings)
  - `nomic-embed-text` (performance embeddings)
  - `all-minilm` (lightweight embeddings)

### LLM-01 Node (`${LLM01_HOST}`)
- **Purpose**: Small, fast models for quick responses
- **Models**:
  - `llama3.2:3b` (balanced performance)
  - `qwen3:1.7b` (speed-optimized)
  - `mistral-small3.2:latest` (general purpose)

### LLM-02 Node (`${LLM02_HOST}`)
- **Purpose**: Large, specialized models for complex tasks
- **Models**:
  - `cogito:32b` (high-quality reasoning)
  - `deepcoder:14b` (code-specialized)
  - `dolphin3:8b` (creative/conversational)
  - `gemma2:2b` (lightweight but capable)
  - `phi3:latest` (Microsoft's efficient model)

## Load Balancer Groups

The gateway provides pre-configured model groups for different use cases:

- **`hx-chat-fast`**: Speed-optimized (qwen3:1.7b on LLM-01)
- **`hx-chat`**: Balanced performance (llama3.2:3b on LLM-01)
- **`hx-chat-code`**: Code-specialized (deepcoder:14b on LLM-02)
- **`hx-chat-premium`**: High-quality reasoning (cogito:32b on LLM-02)
- **`hx-chat-creative`**: Creative/conversational (dolphin3:8b on LLM-02)

## Deployment Notes

1. **Environment Variables**: Always set `HX_MASTER_KEY` before starting the gateway
2. **Network Access**: Ensure the gateway can reach all configured host IPs on the specified ports
3. **Health Checks**: The gateway includes background health checks for all configured models
4. **Security**: All authentication tokens should be generated securely and rotated regularly

## Troubleshooting

### Common Issues

1. **Connection Refused**: Check that Ollama is running on the target host and port
2. **Authentication Errors**: Verify `HX_MASTER_KEY` is set correctly
3. **Model Not Found**: Ensure the model is loaded on the target Ollama instance
4. **Network Issues**: Check firewall rules and network connectivity between nodes

### Validation Commands

```bash
# Test environment variable substitution
envsubst < config-complete.yaml

# Check connectivity to each node
curl -f "${ORC_HOST:-192.168.10.31}:${OLLAMA_PORT:-11434}/api/tags"
curl -f "${LLM01_HOST:-192.168.10.29}:${OLLAMA_PORT:-11434}/api/tags"  
curl -f "${LLM02_HOST:-192.168.10.28}:${OLLAMA_PORT:-11434}/api/tags"
```
