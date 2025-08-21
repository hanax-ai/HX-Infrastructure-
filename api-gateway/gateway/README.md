# HX Gateway (`gateway`) - Technical README

**Version**: 2.0.0  
**Architecture**: `GatewayPipeline` (Chain of Responsibility)
**Primary Contact**: HX-Infra Team

## 1. Overview

This document provides a detailed technical overview of the `gateway` package, the core component of the HX API Gateway. The previous monolithic proxy has been refactored into a modular, testable, and extensible `GatewayPipeline` architecture.

The system is designed around the **Chain of Responsibility** pattern. All incoming API requests are processed by a series of independent middleware components, each handling a specific cross-cutting concern (e.g., security, data transformation, execution).

## 2. Directory Structure

```plaintext
gateway/
├── __init__.py
├── README.md           # This file
├── requirements.lock   # Pinned Python dependencies
├── src/
│   ├── __init__.py
│   ├── app.py          # FastAPI app factory and entrypoint
│   ├── gateway_pipeline.py # Core pipeline orchestrator
│   ├── middlewares/
│   │   ├── __init__.py
│   │   ├── security.py
│   │   ├── transform.py
│   │   └── execution.py
│   └── services/
│       ├── __init__.py
│       └── ... (Future service clients)
└── tests/
    ├── __init__.py
    ├── conftest.py     # Pytest fixtures and test setup
    └── test_pipeline.py # Automated tests for the pipeline
```

## 3. Core Components

### 3.1. `app.py` - Application Entrypoint

- **`build_app()`**: This factory function initializes the FastAPI application.
- **Catch-All Route**: It defines a single, dynamic route:

  ```python
  @app.api_route("/{full_path:path}", methods=["GET", "POST", "PUT", "DELETE"])
  ```

  This route captures all incoming requests, regardless of path or method.
- **Pipeline Instantiation**: For each request, it creates an instance of the `GatewayPipeline` and invokes its `process_request` method, effectively handing off all processing to the pipeline.

### 3.2. `gateway_pipeline.py` - The Orchestrator

This is the heart of the gateway.

- **`__init__(self, config)`**: The constructor initializes the pipeline. It dynamically loads and instantiates the middleware stages defined in the configuration.
- **`process_request(self, request)`**: This is the main processing method. It iterates through the configured middleware stages, passing the request context from one stage to the next. Each stage can modify the request or response before passing it along.
- **Compatibility Shim**: A crucial patch was added to the `__init__` method to ensure `self.stages` is always initialized correctly, preventing `TypeError` exceptions during instantiation. This makes the pipeline robust and backward-compatible.

### 3.3. `middlewares/` - The Processing Stages

Each middleware is a class with a `process_request` method, forming the links in our chain.

- **`SecurityMiddleware`**:
  - **Responsibility**: Handles all authentication and authorization.
  - **Functionality**: Validates `Authorization` headers and ensures the request is allowed to proceed.
- **`TransformMiddleware`**:
  - **Responsibility**: Modifies incoming requests and outgoing responses.
  - **Functionality**: Can be used to reshape data, add/remove headers, or perform other transformations as needed.
- **`ExecutionMiddleware`**:
  - **Responsibility**: Interacts with backend services.
  - **Functionality**: Uses an `httpx.AsyncClient` to forward the processed request to the appropriate downstream service (e.g., LiteLLM, Ollama). It then receives the response to pass back up the chain.

## 4. Testing

The `tests/` directory contains a comprehensive suite of automated tests using `pytest`.

- **`test_pipeline.py`**: This file contains 16 tests that cover the entire request/response lifecycle of the `GatewayPipeline`.
- **`conftest.py`**: Provides fixtures for the tests, such as a test client for the FastAPI application.

### How to Run Tests

Running the tests is the primary method for validating the gateway's functionality.

```bash
# From the /opt/HX-Infrastructure-/api-gateway/ directory

# 1. Set the Python Path
export PYTHONPATH=$(pwd)/gateway

# 2. Set a dummy master key for the test environment
export LITELLM_MASTER_KEY="test-master-key"

# 3. Run pytest
pytest -q gateway/tests/
```

A successful run will show `16 passed`.

## 5. Configuration

The gateway's behavior is driven by configuration files (e.g., `config.yaml`, `model_registry.yaml`) located in `/opt/HX-Infrastructure-/api-gateway/config/`. The `GatewayPipeline` receives this configuration upon initialization and uses it to set up its stages and their behaviors.

## 6. Development Practices

- **Explicit Relative Imports**: All intra-package imports **must** be explicit and relative.
  - **Correct**: `from .middlewares.security import SecurityMiddleware`
  - **Incorrect**: `from middlewares.security import SecurityMiddleware`
- **Dependency Management**: All Python dependencies are pinned in `requirements.lock`. To add or update dependencies, modify the source (e.g., `requirements.in`) and regenerate the lock file.
- **Testing is Mandatory**: Any changes or additions to the pipeline or middleware **must** be accompanied by corresponding tests.

---
**Last Updated**: August 21, 2025

