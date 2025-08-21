# /opt/HX-Infrastructure-/api-gateway/gateway/tests/test_pipeline.py
import os
import pytest
from fastapi import FastAPI, Request
from fastapi.testclient import TestClient
from unittest.mock import patch

# Set environment variables for testing BEFORE importing the app/pipeline
os.environ["HX_MASTER_KEY"] = "test-master-key"
os.environ["HX_LITELLM_UPSTREAM"] = "http://test-upstream"
os.environ["DATABASE_URL"] = "postgresql://user:pass@localhost/db"
os.environ["REDIS_URL"] = "redis://localhost"

# Now, import the components to be tested
from src.app import build_app
from src.middlewares.security import SecurityMiddleware
from src.middlewares.transform import TransformMiddleware

# Create a client for the full application
client = TestClient(build_app())

# --- Middleware Unit Tests ---

@pytest.mark.asyncio
async def test_security_middleware_valid_token():
    """Test SecurityMiddleware with a valid token."""
    middleware = SecurityMiddleware()
    request = Request({
        "type": "http",
        "path": "/v1/models",
        "headers": [(b"authorization", b"Bearer test-master-key")]
    })
    context = {"request": request}
    result_context = await middleware.process(context)
    assert "response" not in result_context

@pytest.mark.asyncio
async def test_security_middleware_invalid_token():
    """Test SecurityMiddleware with an invalid token."""
    middleware = SecurityMiddleware()
    request = Request({
        "type": "http",
        "path": "/v1/models",
        "headers": [(b"authorization", b"Bearer wrong-key")]
    })
    context = {"request": request}
    result_context = await middleware.process(context)
    assert "response" in result_context
    assert result_context["response"].status_code == 401

@pytest.mark.asyncio
async def test_security_middleware_no_token():
    """Test SecurityMiddleware with no token."""
    middleware = SecurityMiddleware()
    request = Request({
        "type": "http",
        "path": "/v1/models",
        "headers": []
    })
    context = {"request": request}
    result_context = await middleware.process(context)
    assert "response" in result_context
    assert result_context["response"].status_code == 401

@pytest.mark.asyncio
async def test_transform_middleware_maps_prompt_to_input():
    """Test TransformMiddleware correctly maps 'prompt' to 'input'."""
    middleware = TransformMiddleware()
    body = b'{"model": "text-embedding-ada-002", "prompt": "hello"}'
    
    async def mock_body():
        return body

    request = Request({
        "type": "http",
        "path": "/v1/embeddings",
        "method": "POST",
        "headers": [],
    })
    request.body = mock_body

    context = {"request": request}
    result_context = await middleware.process(context)
    
    assert "response" not in result_context
    assert "transformed_body" in result_context
    import json
    transformed_payload = json.loads(result_context["transformed_body"])
    assert "input" in transformed_payload
    assert "prompt" not in transformed_payload
    assert transformed_payload["input"] == "hello"

@pytest.mark.asyncio
async def test_transform_middleware_ignores_other_paths():
    """Test TransformMiddleware ignores paths other than /v1/embeddings."""
    middleware = TransformMiddleware()
    request = Request({
        "type": "http",
        "path": "/v1/chat/completions",
        "method": "POST",
        "headers": [],
    })
    context = {"request": request}
    result_context = await middleware.process(context)
    assert "transformed_body" not in result_context

# --- Full Pipeline Smoke Test ---

@patch("src.middlewares.execution.httpx.AsyncClient.request")
def test_full_pipeline_smoke_test_success(mock_request):
    """Smoke test for a successful request through the entire pipeline."""
    # Mock the final execution call to the upstream service
    mock_request.return_value.status_code = 200
    mock_request.return_value.content = b'{"data": "success"}'
    mock_request.return_value.headers = {}

    response = client.get(
        "/v1/models",
        headers={"Authorization": "Bearer test-master-key"}
    )
    
    assert response.status_code == 200
    assert response.json() == {"data": "success"}
    mock_request.assert_called_once()

@patch("src.middlewares.execution.httpx.AsyncClient.request")
def test_full_pipeline_smoke_test_auth_failure(mock_request):
    """Smoke test for a failed authentication request."""
    response = client.get(
        "/v1/models",
        headers={"Authorization": "Bearer wrong-key"}
    )
    
    assert response.status_code == 401
    assert "Unauthorized" in response.text
    # The execution middleware should not be called if auth fails
    mock_request.assert_not_called()
