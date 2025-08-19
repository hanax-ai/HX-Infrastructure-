# HX Gateway Wrapper - Dependency Management Documentation

## Overview

The HX Gateway Wrapper follows SOLID principles in its dependency management strategy, implementing a minimal viable dependency set that supports the complete middleware pipeline while maintaining extensibility for future enhancements.

## SOLID Compliance in Dependency Design

### Single Responsibility Principle
Each dependency serves a single, well-defined purpose:
- **FastAPI**: Async web framework and request handling
- **Uvicorn**: ASGI server for production deployment  
- **HTTPX**: Async HTTP client for upstream communication
- **PyYAML**: Configuration file parsing

### Open/Closed Principle
The dependency set is closed for modification but open for extension:
- Core dependencies remain stable
- Future ML/monitoring deps can be added without changing existing code
- Modular installation allows selective feature additions

### Liskov Substitution Principle
Dependencies are abstracted through interfaces:
- HTTP client abstracted in ExecutionMiddleware
- Config parsing abstracted in RoutingMiddleware
- Server runtime abstracted from application logic

### Interface Segregation Principle
Each component only depends on what it needs:
- SecurityMiddleware: Only FastAPI Request/Response
- RoutingMiddleware: Only YAML parsing capability
- ExecutionMiddleware: Only HTTP client functionality

### Dependency Inversion Principle
High-level modules don't depend on low-level modules:
- Pipeline depends on abstract MiddlewareBase, not concrete implementations
- Configuration loading depends on abstract file interface
- HTTP communication depends on abstract client interface

## Dependency Categories

### Core Web Framework
```python
# FastAPI - Modern async web framework
# Provides: Request/Response handling, middleware support, OpenAPI docs
# Used by: main.py, all middleware components
# SOLID Role: Foundation for Request/Response abstraction

# Uvicorn - ASGI server implementation  
# Provides: Production-ready async server
# Used by: Deployment and development
# SOLID Role: Runtime environment abstraction
```

### HTTP Communication
```python
# HTTPX - Async HTTP client
# Provides: Non-blocking upstream requests to LiteLLM
# Used by: ExecutionMiddleware
# SOLID Role: Abstract HTTP client interface for upstream communication
```

### Configuration Management
```python
# PyYAML - YAML parsing library
# Provides: Configuration file parsing for model registry and routing
# Used by: RoutingMiddleware for loading configs
# SOLID Role: Abstract configuration source interface
```

## Future Extension Points

### ML and Analytics Dependencies
```bash
# When ML routing features mature:
pip install scikit-learn pandas numpy

# Purpose: Enhanced model selection algorithms
# Integration: routing/features.py and routing/selector.py
# SOLID Impact: Extends existing interfaces without modification
```

### Monitoring and Observability
```bash
# When production monitoring is needed:
pip install prometheus-client redis

# Purpose: Metrics collection and caching
# Integration: New monitoring middleware component
# SOLID Impact: Adds new middleware without changing existing ones
```

### Security Enhancements
```bash
# When advanced auth is needed:
pip install cryptography authlib

# Purpose: JWT validation, OAuth2, encryption
# Integration: Enhanced SecurityMiddleware
# SOLID Impact: Extends security interface without breaking changes
```

### Testing Infrastructure
```bash
# For comprehensive testing:
pip install pytest httpx pytest-asyncio

# Purpose: Unit tests, integration tests, async testing
# Integration: tests/ directory structure
# SOLID Impact: Tests validate interface contracts
```

## Installation Architecture

### Virtual Environment Strategy
```bash
# Isolated dependency management
VENV="/opt/HX-Infrastructure-/api-gateway/gateway/venv"

# Benefits:
# - Prevents system Python conflicts
# - Enables clean rollbacks
# - Supports multiple deployment environments
# - Follows Dependency Inversion principle
```

### Dependency Resolution Strategy
```bash
# Minimal viable set approach:
# 1. Install only what's needed for current features
# 2. Validate each dependency import
# 3. Document extension points for future needs
# 4. Maintain backward compatibility
```

## Usage Examples

### Development Setup
```bash
# Quick development environment
cd /opt/HX-Infrastructure-/api-gateway/gateway/src
source ../venv/bin/activate
uvicorn main:app --reload --host 0.0.0.0 --port 4010
```

### Production Deployment
```bash
# Production-ready server
source /opt/HX-Infrastructure-/api-gateway/gateway/venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 4010 --workers 4
```

### Health Verification
```bash
# Verify wrapper is running
curl http://localhost:4010/healthz

# Expected response:
{"status": "ok"}
```

## Error Handling

### Missing Dependencies
```python
# Each middleware gracefully handles missing optional dependencies
try:
    import optional_ml_lib
except ImportError:
    # Fallback to basic functionality
    optional_ml_lib = None
```

### Version Conflicts
```bash
# Virtual environment prevents system conflicts
# Each deployment uses isolated dependency versions
# pip freeze > requirements.txt for reproducible builds
```

### Import Validation
```python
# Installation script validates all imports
python -c "
import fastapi, uvicorn, httpx, yaml
print('✅ All dependencies successfully imported')
"
```

## Integration with SOLID Architecture

### Request Flow Dependency Usage
1. **FastAPI Request** → SecurityMiddleware (FastAPI objects)
2. **Validation** → ValidationMiddleware (FastAPI Response)  
3. **Transform** → TransformMiddleware (JSON parsing)
4. **Route** → RoutingMiddleware (YAML config loading)
5. **Execute** → ExecutionMiddleware (HTTPX client)
6. **FastAPI Response** → Client

### Configuration Dependency Chain
```
YAML Files → PyYAML → RoutingMiddleware → ModelSelectionAlgorithm
Model Registry → Features → Scoring → Selection
```

### Communication Dependency Chain  
```
FastAPI Request → Context Dict → HTTPX → LiteLLM → FastAPI Response
```

This dependency management strategy ensures the HX Gateway Wrapper maintains SOLID principles while providing a foundation for future ML and monitoring enhancements.
