#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

echo "=== [HX-INFRASTRUCTURE] BEGIN: LiteLLM API Gateway Deployment ==="

# ---------- Config ----------
BASE_DIR="/opt/HX-Infrastructure-/api-gateway"
CONFIG_DIR="${BASE_DIR}/config/api-gateway"
GWAY_DIR="${BASE_DIR}/gateway"
VENV_DIR="${GWAY_DIR}/venv"
SVC_DIR="${BASE_DIR}/scripts/service/api-gateway"
LOG_DIR="${BASE_DIR}/logs/services"
DEPLOY_DIR="${BASE_DIR}/scripts/deployment"

# Fleet IPs (update only if your network changes)
LLM01_IP="192.168.10.29"
LLM02_IP="192.168.10.28"
ORC_IP="192.168.10.31"
GW_IP="192.168.10.39"     # this server must own this IP
GW_HOST="0.0.0.0"
GW_PORT="4000"
# Security validation - REQUIRE MASTER_KEY to be set externally  
if [[ -z "${MASTER_KEY:-}" ]]; then
    echo "❌ ERROR: MASTER_KEY environment variable is required" >&2
    echo "   This must be set to a secure value before running deployment" >&2
    echo "   Example: export MASTER_KEY='sk-hx-your-secure-production-key'" >&2
    exit 1
fi

# Validate MASTER_KEY security
if [[ "${MASTER_KEY}" == *"sk-hx-dev"* ]] || [[ "${MASTER_KEY}" == *"1234"* ]] || [[ ${#MASTER_KEY} -lt 32 ]]; then
    echo "❌ ERROR: Insecure MASTER_KEY detected" >&2
    echo "   Development keys or short keys are not allowed in deployment" >&2
    echo "   Please use a secure, randomly generated key (minimum 32 characters)" >&2
    exit 1
fi

CONFIG_FILE="${CONFIG_DIR}/config.yaml"
SERVICE_FILE="/etc/systemd/system/hx-litellm-gateway.service"

# ---------- Pre-check: Critical binaries ----------
echo "--> Pre-check: Verifying critical binaries are available..."
if ! command -v ip >/dev/null 2>&1; then
    echo "❌ CRITICAL ERROR: 'ip' command not found."
    echo "   The 'ip' command is required for server identity verification."
    echo "   Please install iproute2 package: sudo apt-get install iproute2"
    exit 1
fi
echo "✅ Critical binary check passed."

# ---------- Step 0: Wrong-server guard ----------
echo "--> Step 0: Verifying this is the API gateway server (${GW_IP})..."
if [ "${FORCE:-0}" != "1" ]; then
  if ! ip -o -4 addr show scope global | awk '{print $4}' | cut -d/ -f1 | grep -qx "${GW_IP}"; then
    echo "❌ REFUSING TO RUN: This host does not own ${GW_IP}."
    echo "   If you're absolutely sure, re-run with FORCE=1 (e.g., FORCE=1 bash deploy-litellm-gateway.sh)"
    exit 1
  fi
fi
echo "✅ Server identity check passed."

# ---------- Step 1: Preflight ----------
echo "--> Step 1: Preflight checks..."
for bin in python3 curl jq ip; do
  command -v "$bin" >/dev/null || { echo "❌ Missing required command: $bin"; exit 1; }
done
echo "✅ Binaries present."

# ---------- Step 2: Ensure directories -----------
echo "--> Step 2: Ensuring directory scaffold..."
sudo mkdir -p "${CONFIG_DIR}" "${GWAY_DIR}" "${SVC_DIR}" "${LOG_DIR}" "${DEPLOY_DIR}"
echo "✅ Directories ready under ${BASE_DIR}"

# ---------- Step 3: OS packages (venv/pip) ----------
echo "--> Step 3: Installing OS packages (python3-venv, pip, build utils)..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y >/dev/null
sudo apt-get install -y python3-venv python3-pip python3-dev build-essential >/dev/null
echo "✅ OS deps installed."

# ---------- Step 4: Create venv & install litellm[proxy] ----------
echo "--> Step 4: Creating venv and installing LiteLLM proxy + deps..."
if [ ! -d "${VENV_DIR}" ]; then
  sudo python3 -m venv "${VENV_DIR}"
fi
sudo bash -c "source '${VENV_DIR}/bin/activate' \
  && pip install --upgrade pip setuptools wheel >/dev/null \
  && (pip install 'litellm==1.74.15' >/dev/null || pip install 'litellm' >/dev/null) \
  && pip install 'litellm[proxy]' 'uvicorn[standard]' 'fastapi' 'backoff' >/dev/null"
# smoke the binary
"${VENV_DIR}/bin/litellm" --help >/dev/null
echo "✅ LiteLLM proxy installed in ${VENV_DIR}"

# ---------- Step 5: Backend reachability (soft check) ----------
echo "--> Step 5: Backend reachability (soft check, non-fatal)..."
for url in \
  "http://${ORC_IP}:11434/api/version" \
  "http://${LLM01_IP}:11434/api/version" \
  "http://${LLM02_IP}:11434/api/version"
do
  if curl -fsS --max-time 3 "$url" >/dev/null; then
    echo "  ✔ reachable: $url"
  else
    echo "  ⚠ WARN: not reachable now: $url (continuing)"
  fi
done

# ---------- Step 6: Write LiteLLM config ----------
echo "--> Step 6: Writing ${CONFIG_FILE}..."
sudo tee "${CONFIG_FILE}" >/dev/null <<YAML
general_settings:
  master_key: ${MASTER_KEY}
  background_health_checks: false

model_list:
  # --- Embeddings (orc) ---
  - model_name: emb-premium
    litellm_params: { model: "ollama/mxbai-embed-large", api_base: "http://${ORC_IP}:11434" }
  - model_name: emb-perf
    litellm_params: { model: "ollama/nomic-embed-text",  api_base: "http://${ORC_IP}:11434" }
  - model_name: emb-light
    litellm_params: { model: "ollama/all-minilm",       api_base: "http://${ORC_IP}:11434" }

  # --- Chat/Instruct (llm-01 + llm-02) ---
  - model_name: llm01-llama3.2-3b
    litellm_params: { model: "ollama/llama3.2:3b", api_base: "http://${LLM01_IP}:11434" }
  - model_name: llm02-phi3
    litellm_params: { model: "ollama/phi3:latest", api_base: "http://${LLM02_IP}:11434" }
  - model_name: llm02-gemma2-2b
    litellm_params: { model: "ollama/gemma2:2b",   api_base: "http://${LLM02_IP}:11434" }

router_settings:
  model_group:
    hx-chat:
      - "llm01-llama3.2-3b"
      - "llm02-phi3"
      - "llm02-gemma2-2b"
YAML
grep -q "${ORC_IP}" "${CONFIG_FILE}" && echo "✅ Config written." || { echo "❌ Config write failed"; exit 1; }

# ---------- Step 6.5: Create dedicated system user ----------
echo "--> Step 6.5: Creating dedicated system user for gateway service..."
GATEWAY_USER="hx-gateway"
if ! id "${GATEWAY_USER}" >/dev/null 2>&1; then
  sudo useradd --system --shell /bin/false --home-dir /nonexistent --no-create-home "${GATEWAY_USER}"
  echo "✅ Created system user: ${GATEWAY_USER}"
else
  echo "✅ System user already exists: ${GATEWAY_USER}"
fi

# Set ownership and permissions for gateway directories
echo "--> Setting ownership and permissions for ${GATEWAY_USER}..."
sudo chown -R "${GATEWAY_USER}:${GATEWAY_USER}" "${GWAY_DIR}" "${LOG_DIR}"
sudo chown "${GATEWAY_USER}:${GATEWAY_USER}" "${CONFIG_FILE}"
sudo chmod -R 755 "${GWAY_DIR}" "${LOG_DIR}"
sudo chmod 644 "${CONFIG_FILE}"

# Ensure venv is accessible to the gateway user
if [ -d "${VENV_DIR}" ]; then
  sudo chown -R "${GATEWAY_USER}:${GATEWAY_USER}" "${VENV_DIR}"
  sudo find "${VENV_DIR}" -type d -exec chmod 755 {} \;
  sudo find "${VENV_DIR}" -type f -executable -exec chmod 755 {} \;
  sudo find "${VENV_DIR}" -type f ! -executable -exec chmod 644 {} \;
fi
echo "✅ Permissions set for ${GATEWAY_USER}"

# ---------- Step 7: Systemd unit ----------
echo "--> Step 7: Creating systemd unit..."
sudo tee "${SERVICE_FILE}" >/dev/null <<EOF
[Unit]
Description=HX LiteLLM API Gateway (OpenAI-compatible)
After=network-online.target
Wants=network-online.target

[Service]
User=${GATEWAY_USER}
Group=${GATEWAY_USER}
WorkingDirectory=${GWAY_DIR}
ExecStart=${VENV_DIR}/bin/litellm --host ${GW_HOST} --port ${GW_PORT} --config ${CONFIG_FILE}
Restart=on-failure
Environment=PYTHONUNBUFFERED=1

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
echo "✅ systemd unit installed: $(basename "${SERVICE_FILE}")"

# Stop service if it's running (to apply new user settings)
if sudo systemctl is-active --quiet hx-litellm-gateway; then
  echo "--> Stopping existing service to apply user changes..."
  sudo systemctl stop hx-litellm-gateway
  sleep 2
fi

# ---------- Step 8: HX service scripts ----------
echo "--> Step 8: Installing HX service scripts..."
sudo tee "${SVC_DIR}/start.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "Executing: Start HX LiteLLM Gateway"
sudo systemctl enable hx-litellm-gateway >/dev/null 2>&1 || true
sudo systemctl start hx-litellm-gateway
sleep 5
if sudo systemctl is-active --quiet hx-litellm-gateway; then
  echo "HX LiteLLM Gateway started successfully!"
else
  echo "ERROR: HX LiteLLM Gateway failed to start." >&2; exit 1
fi
EOF

sudo tee "${SVC_DIR}/stop.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "Executing: Stop HX LiteLLM Gateway"
sudo systemctl stop hx-litellm-gateway
sleep 5
if ! sudo systemctl is-active --quiet hx-litellm-gateway; then
  echo "HX LiteLLM Gateway stopped successfully!"
else
  echo "ERROR: HX LiteLLM Gateway failed to stop." >&2; exit 1
fi
EOF

sudo tee "${SVC_DIR}/status.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "HX LiteLLM Gateway status:"
sudo systemctl status --no-pager hx-litellm-gateway || true
echo "--- logs (last 20) ---"
sudo journalctl -u hx-litellm-gateway -n 20 --no-pager || true
echo "--- API health (/v1/models) ---"
curl -fsS --max-time 10 http://127.0.0.1:4000/v1/models \
  -H "Authorization: Bearer ${MASTER_KEY}" \
  -H "Content-Type: application/json" >/dev/null \
  && echo "✅ Gateway responding" || { echo "❌ Gateway not responding"; exit 1; }
EOF

sudo chmod +x "${SVC_DIR}/start.sh" "${SVC_DIR}/stop.sh" "${SVC_DIR}/status.sh"
echo "✅ HX scripts installed: ${SVC_DIR}"

# ---------- Step 9: Start service ----------
echo "--> Step 9: Starting service..."
"${SVC_DIR}/start.sh"
"${SVC_DIR}/status.sh"

# ---------- Step 10: Live validations ----------
echo "--> Step 10: Live validations..."

echo "[a] /v1/models should return a non-empty list"
curl -fsS http://127.0.0.1:${GW_PORT}/v1/models \
  -H "Authorization: Bearer ${MASTER_KEY}" -H "Content-Type: application/json" \
  | jq -e '.data | length > 0' >/dev/null && echo "  ✔ models OK" || { echo "  ✖ models failed"; exit 1; }

echo "[b] Embeddings (emb-premium 1024-dim) with OpenAI-style 'input'"
curl -fsS http://127.0.0.1:${GW_PORT}/v1/embeddings \
  -H "Authorization: Bearer ${MASTER_KEY}" -H "Content-Type: application/json" \
  -d '{"model":"emb-premium","input":"HX Gateway is operational."}' \
  | jq -e '.data[0].embedding | length == 1024' >/dev/null && echo "  ✔ embeddings OK" || { echo "  ✖ embeddings failed"; exit 1; }

echo "[c] Chat (hx-chat) non-stream exact echo"
curl -fsS http://127.0.0.1:${GW_PORT}/v1/chat/completions \
  -H "Authorization: Bearer ${MASTER_KEY}" -H "Content-Type: application/json" \
  -d '{"model":"hx-chat","messages":[{"role":"user","content":"Return exactly the text: HX-OK"}],"max_tokens":10,"temperature":0}' \
  | jq -r '.choices[0].message.content' | grep -q 'HX-OK' && echo "  ✔ chat OK" || { echo "  ✖ chat failed"; exit 1; }

echo
echo "=== [HX-INFRASTRUCTURE] END: LiteLLM API Gateway Deployment COMPLETE ✅ ==="
