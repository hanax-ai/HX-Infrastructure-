This is an excellent, well-defined engineering task plan. It provides all the necessary detail to ensure a high-quality implementation and aligns perfectly with our standards.

I have incorporated this into a formal implementation and validation plan.

Implementation Plan: GatewayPipeline RAG Search Endpoint
Purpose: This plan outlines the operational steps to deploy, configure, and validate the new /v1/rag/search endpoint within the refactored GatewayPipeline architecture. This feature is enabled via the ENABLE_RAG feature flag for safe rollout and rollback.

Step 1: Deploy RAG Feature Code and Dependencies
This step involves deploying the new Python source code and ensuring all required package dependencies are met. The deployment will introduce the new route (routes/rag.py) and its supporting services (services/rag_embeddings.py, services/rag_qdrant.py).

Task:

Bash

# 1. In a real-world scenario, this would be a 'git pull' from our repository.
#    For this plan, we will confirm the presence of the key files.
#    (The engineering team is responsible for placing the correct files during CI/CD)

# 2. Ensure the httpx dependency is installed in the service venv
VENV="/opt/HX-Infrastructure-/api-gateway/gateway/venv"
echo "Ensuring httpx dependency is installed..."
sudo $VENV/bin/pip install -q "httpx>=0.27"
Validation:

Bash

# 1. Verify that the primary route file has been deployed
if [ -f "/opt/HX-Infrastructure-/api-gateway/gateway/src/routes/rag.py" ]; then
    echo "✅ Code Validation: RAG route file is present."
else
    echo "❌ Code Validation: RAG route file is missing."
    exit 1
fi

# 2. Verify dependency installation with a quick import check
$VENV/bin/python -c "import httpx; print('✅ Dependency Validation: httpx is installed.')"
Step 2: Configure and Enable the RAG Feature
We will enable the new endpoint by setting the ENABLE_RAG environment variable within the systemd service configuration.

Task:

Bash

# Create or amend the systemd override file for the gateway service
sudo systemctl edit hx-litellm-gateway
Inside the editor, ensure the following Environment directive is present within the [Service] section. Add it if it's not there.

Ini, TOML

[Service]
Environment="ENABLE_RAG=true"
Validation:

Bash

# Reload the systemd daemon to ingest the change
sudo systemctl daemon-reload

# Verify that the environment variable is loaded for the service
systemctl show hx-litellm-gateway | grep ENABLE_RAG
Step 3: Restart and Verify the Service
With the new code and configuration in place, we will restart the gateway service to activate the /v1/rag/search endpoint.

Task:

Bash

# STOP the service
echo "Stopping HX LiteLLM Gateway..."
sudo systemctl stop hx-litellm-gateway
sleep 5
if ! sudo systemctl is-active --quiet hx-litellm-gateway; then
  echo "HX Gateway stopped successfully!"
else
  echo "ERROR: HX Gateway failed to stop." >&2; exit 1
fi

# START the service
echo "Starting HX LiteLLM Gateway with RAG endpoint enabled..."
sudo systemctl start hx-litellm-gateway
sleep 5
if sudo systemctl is-active --quiet hx-litellm-gateway; then
  echo "HX Gateway started successfully!"
else
  echo "ERROR: HX Gateway failed to start." >&2
  journalctl -u hx-litellm-gateway -n 200 --no-pager
  exit 1
fi
Validation:

Bash

# Check that the service is active
sudo systemctl is-active --quiet hx-litellm-gateway && echo "✅ Service is active." || echo "❌ Service failed to start."
Step 4: Execute Validation Test Suite
This final step executes the full test suite against the live endpoint to confirm all requirements have been met.

Task & Validation:

Bash

# --- Test Setup ---
BASE_URL="http://127.0.0.1:4000"
# NOTE: Use a valid, previously generated user key for this test
AUTH_HEADER="Authorization: Bearer sk-mDyhCELJX..."

# --- Test Case 1: Query Path (Requires Auth) ---
echo "--- 1. Testing Query Path (expects 200 OK) ---"
STATUS_1=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "$AUTH_HEADER" -H "Content-Type: application/json" \
  -d '{"query":"hello world","limit":3}' \
  "$BASE_URL/v1/rag/search")
[ "$STATUS_1" -eq 200 ] && echo "✅ PASSED" || echo "❌ FAILED (Status: $STATUS_1)"

# --- Test Case 2: Vector Path (Requires Auth) ---
echo "--- 2. Testing Vector Path (expects 200 OK) ---"
STATUS_2=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "$AUTH_HEADER" -H "Content-Type: application/json" \
  -d '{"vector":[0.01,0,0.02,0.03,0], "limit":3}' \
  "$BASE_URL/v1/rag/search")
[ "$STATUS_2" -eq 200 ] && echo "✅ PASSED" || echo "❌ FAILED (Status: $STATUS_2)"

# --- Test Case 3: Auth Required for Query Path ---
echo "--- 3. Testing Auth Requirement (expects 401 Unauthorized) ---"
STATUS_3=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -d '{"query":"hello"}' \
  "$BASE_URL/v1/rag/search")
[ "$STATUS_3" -eq 401 ] && echo "✅ PASSED" || echo "❌ FAILED (Status: $STATUS_3)"

# --- Test Case 4: Input Validation ---
echo "--- 4. Testing Input Validation (expects 400 Bad Request) ---"
STATUS_4=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "$AUTH_HEADER" -H "Content-Type: application/json" \
  -d '{}' \
  "$BASE_URL/v1/rag/search")
[ "$STATUS_4" -eq 400 ] && echo "✅ PASSED" || echo "❌ FAILED (Status: $STATUS_4)"
Rollback Procedure
If the validation tests fail or an immediate rollback is required, the RAG feature can be disabled instantly via its feature flag without a code change.

Task:

Bash

# Open the systemd override editor
sudo systemctl edit hx-litellm-gateway
Change the Environment directive from true to false:

Ini, TOML

[Service]
Environment="ENABLE_RAG=false"
Validation:

Bash

# Reload and restart the service
sudo systemctl daemon-reload
sudo systemctl restart hx-litellm-gateway
sleep 5

# Confirm the service is active
sudo systemctl is-active --quiet hx-litellm-gateway && echo "✅ Service reverted successfully."

# Confirm the RAG endpoint is no longer available (expects 404 Not Found)
STATUS_ROLLBACK=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" -H "Content-Type: application/json" -d '{"query":"test"}' "$BASE_URL/v1/rag/search")
[ "$STATUS_ROLLBACK" -eq 404 ] && echo "✅ Rollback Validated: RAG endpoint is disabled (404 Not Found)." || echo "❌ Rollback Failed (Status: $STATUS_ROLLBACK)"











Tools


