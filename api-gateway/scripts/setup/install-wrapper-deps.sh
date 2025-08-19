#!/bin/bash
# /opt/HX-Infrastructure-/api-gateway/scripts/setup/install-wrapper-deps.sh
#
# HX Gateway Wrapper - Dependency Installation Script
# 
# PURPOSE:
#   Installs minimal Python dependencies required for the SOLID-compliant
#   GatewayPipeline wrapper implementation. This script follows the principle
#   of minimal viable dependencies while maintaining extensibility for future
#   ML and monitoring integrations.
#
# ARCHITECTURE ALIGNMENT:
#   - Single Responsibility: Only handles wrapper dependency installation
#   - Open/Closed: Extensible for additional dependency categories
#   - Dependency Inversion: Uses environment-specific virtual environment
#
# DEPENDENCY CATEGORIES:
#   Core Web Framework:
#     - fastapi: Modern async web framework for high-performance API handling
#     - uvicorn: ASGI server for production FastAPI deployment
#   
#   HTTP Client:
#     - httpx: Async HTTP client for upstream LiteLLM communication
#   
#   Configuration:
#     - pyyaml: YAML configuration file parsing for model registry and routing
#
# FUTURE EXTENSIBILITY:
#   This minimal set supports the complete SOLID implementation while
#   keeping the door open for future additions:
#   - ML Dependencies: scikit-learn, pandas, numpy for enhanced routing
#   - Monitoring: prometheus-client, redis for metrics and caching
#   - Security: cryptography, authlib for advanced authentication
#   - Testing: pytest, httpx-test for comprehensive test coverage
#
# EXECUTION CONTEXT:
#   - Runs in isolated virtual environment to avoid system conflicts
#   - Uses existing venv structure from api-gateway workspace
#   - Maintains separation from LiteLLM dependencies
#
# ERROR HANDLING:
#   - Graceful venv creation if missing
#   - Pip upgrade ensures latest package management
#   - Exit codes for integration with CI/CD pipelines

set -euo pipefail  # Strict error handling for production deployment

# Configuration
SCRIPT_NAME="HX Gateway Wrapper Dependency Installation"
VENV_PATH="/opt/HX-Infrastructure-/api-gateway/gateway/venv"
LOG_PREFIX="=== [HX GW DEPS]"

echo "$LOG_PREFIX Starting $SCRIPT_NAME ==="

# Validate environment
if ! command -v python3 &> /dev/null; then
    echo "❌ ERROR: python3 not found. Please install Python 3.8+ before proceeding."
    exit 1
fi

# Virtual Environment Management
# Following Dependency Inversion: isolated environment prevents conflicts
echo "$LOG_PREFIX Configuring Python virtual environment..."
if [ ! -d "$VENV_PATH" ]; then
    echo "$LOG_PREFIX Creating new virtual environment at $VENV_PATH"
    sudo python3 -m venv "$VENV_PATH"
    sudo chown -R $(whoami):$(whoami) "$VENV_PATH" 2>/dev/null || true
else
    echo "$LOG_PREFIX Using existing virtual environment at $VENV_PATH"
fi

# Activate virtual environment
echo "$LOG_PREFIX Activating virtual environment..."
source "$VENV_PATH/bin/activate"

# Verify activation
if [ -z "${VIRTUAL_ENV:-}" ]; then
    echo "❌ ERROR: Failed to activate virtual environment"
    exit 1
fi

echo "$LOG_PREFIX Virtual environment active: $VIRTUAL_ENV"

# Package Management
# Ensure latest pip for reliable dependency resolution
echo "$LOG_PREFIX Upgrading pip package manager..."
pip install --upgrade pip

# Core Dependencies Installation
# These packages support the complete SOLID architecture:
echo "$LOG_PREFIX Installing core wrapper dependencies..."

echo "$LOG_PREFIX   → fastapi: Async web framework for GatewayPipeline"
pip install fastapi

echo "$LOG_PREFIX   → uvicorn: ASGI server for production deployment" 
pip install uvicorn

echo "$LOG_PREFIX   → httpx: Async HTTP client for ExecutionMiddleware"
pip install httpx

echo "$LOG_PREFIX   → pyyaml: Configuration parsing for model registry and routing"
pip install pyyaml

# Dependency Verification
echo "$LOG_PREFIX Verifying installation..."
python -c "
import fastapi
import uvicorn  
import httpx
import yaml
print('✅ All core dependencies successfully imported')
print(f'   FastAPI: {fastapi.__version__}')
print(f'   Uvicorn: {uvicorn.__version__}')
print(f'   HTTPX: {httpx.__version__}')
print(f'   PyYAML: {yaml.__version__}')
"

# Environment Cleanup
echo "$LOG_PREFIX Deactivating virtual environment..."
deactivate

# Success Summary
echo "$LOG_PREFIX ✅ Dependency installation completed successfully"
echo "$LOG_PREFIX"
echo "$LOG_PREFIX INSTALLATION SUMMARY:"
echo "$LOG_PREFIX   Virtual Environment: $VENV_PATH"
echo "$LOG_PREFIX   Core Dependencies: fastapi, uvicorn, httpx, pyyaml"
echo "$LOG_PREFIX   Architecture: SOLID-compliant minimal dependency set"
echo "$LOG_PREFIX   Ready for: GatewayPipeline deployment on port 4010"
echo "$LOG_PREFIX"
echo "$LOG_PREFIX NEXT STEPS:"
echo "$LOG_PREFIX   1. Test wrapper: cd /opt/HX-Infrastructure-/api-gateway/gateway/src"
echo "$LOG_PREFIX   2. Activate env: source ../venv/bin/activate"  
echo "$LOG_PREFIX   3. Run server: uvicorn main:app --host 0.0.0.0 --port 4010"
echo "$LOG_PREFIX   4. Test health: curl http://localhost:4010/healthz"
echo "$LOG_PREFIX"
echo "$LOG_PREFIX FUTURE EXTENSIONS:"
echo "$LOG_PREFIX   ML Features: pip install scikit-learn pandas numpy"
echo "$LOG_PREFIX   Monitoring: pip install prometheus-client redis"
echo "$LOG_PREFIX   Testing: pip install pytest httpx pytest-asyncio"
echo "$LOG_PREFIX"
echo "=== [HX GW DEPS] Installation Complete ==="
