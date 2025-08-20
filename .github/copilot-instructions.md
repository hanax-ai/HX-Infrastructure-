# HX-Infrastructure AI Agent Instructions

This document provides essential guidelines for working within the HX-Infrastructure repository. Adhering to these standards is mandatory for all contributions.

## 🏗️ Architecture Overview

The HX-Infrastructure is a multi-node platform for deploying and managing Large Language Models (LLMs). The core components are:
- **`api-gateway`**: A SOLID-compliant reverse proxy for LiteLLM backends. It handles request transformation and routing.
- **`llm-01`**: The primary production LLM inference node.
- **`llm-02`**: A baseline reference node, architecturally aligned with `llm-01`.
- **`orc`**: An orchestration server dedicated to text embedding models and services.
- **`lib/` & `scripts/`**: Centralized locations for shared libraries and scripts that are symlinked by the individual services.

The architecture heavily emphasizes standardization. All nodes use shared service management scripts and canonical storage paths like `/mnt/active_llm_models`.

## ⚙️ Key Conventions & Standards

Refer to the main engineering standards in `.rules` for detailed protocols.

1.  **Configuration Management (Rule 0.25)**:
    - **No hardcoded values.** All configuration must be in `.env` or `.yaml` files.
    - Service configurations are typically located in `/{component}/config/ollama/`. For example, `llm-01/config/ollama/ollama.env`.
    - The `OLLAMA_MODELS_AVAILABLE` variable in `ollama.env` is the single source of truth for the models a service provides.

2.  **File System (Rule 0.26)**:
    - Follow the existing directory structure. New scripts go into `scripts/`, shared libraries into `lib/`, and component-specific code into the component's directory.
    - Service scripts are standardized. For example, each service has `scripts/service/` which is often a symlink to the global `/opt/scripts/service/ollama/` in production.

3.  **Documentation (MANDATORY)**:
    - After **every** change, you **must** update the relevant documentation in the component's `x-Docs/` directory.
    - **Deployment Status**: Update `x-Docs/deployment-status-tracker.md` with the status (✅ COMPLETED, 🔄 PENDING, ❌ FAILED), timestamp, and validation results.
    - **Code Enhancements**: Update `x-Docs/code-enhancements.md` with a description of the problem, solution, and benefits.

## Critical Workflows

### Service Management

All services follow a standard lifecycle management protocol using shared scripts. When asked to manage a service, use these scripts.

```bash
# Start a service (and verify)
/opt/scripts/service/ollama/start.sh

# Stop a service
/opt/scripts/service/ollama/stop.sh

# Check service status
/opt/scripts/service/ollama/status.sh
```

### Model & Configuration Validation

Before deploying any changes related to model configuration, you **must** run the validation script. This is a critical step to prevent misconfigurations.

```bash
# Validate the model configuration for a component
./validate-model-config.sh {path_to_component}/config/ollama/ollama.env
```

### Testing

The repository contains a suite of tests for different purposes.
- **Smoke Tests**: For quick, basic functionality checks.
- **Comprehensive Tests**: For more thorough validation.
- **Performance Tests**: Located in `orc/scripts/tests/perf/embeddings/` for the embedding service.

```bash
# Run a basic smoke test for a service
/opt/scripts/tests/smoke/ollama/smoke.sh

# Run the comprehensive test suite
/opt/scripts/tests/smoke/ollama/comprehensive-smoke.sh
```

### External Verification

For services that need to be accessed externally, use the `emb-external-verify.sh` script.

```bash
# Verify external connectivity to a host
./emb-external-verify.sh <HOST_IP> [PORT]
```
