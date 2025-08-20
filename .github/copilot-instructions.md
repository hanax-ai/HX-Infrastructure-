GitHub Copilot – Project Instructions (HX-Infrastructure) (Revised)
Purpose
These instructions shape Copilot suggestions for the HX-Infrastructure repository. The goals are: (1) enforce architecture and coding standards, (2) prefer explicit, well-validated steps, and (3) align output with our stack (FastAPI Gateway, Ollama-based LLM servers, Orchestration/Embeddings, Jenkins+Ansible CI/CD, Terraform, PostgreSQL/Redis).

Project Context (Authoritative)
Single root: /opt/HX-Infrastructure-

Primary components:

API Gateway: FastAPI, OpenAI-compatible endpoints (/v1/chat/completions, /v1/models), httpx, pydantic-settings.

LLM Servers: Ollama 0.10.x, single-port (11434), multiple models via model ID.

Models in active use: Mixtral-8x7B, DeepSeek-R1 (coder 14B variant), Nous Hermes 2 Mixtral 8x7B DPO, Phi-3 Mini 4K Instruct, Yi-34B (as applicable), OpenChat 3.5, MiMo-VL-7B, imp-v1-3b.

Data tier: PostgreSQL 17.x (5432) + Pgpool-II (5433), Redis 8.x (6379).

Observability: Prometheus/Grafana off-box; services emit metrics only.

Automation: Jenkins pipelines trigger Ansible playbooks; Terraform for infra as code.

Global Principles
SOLID/OOP (when applicable): single responsibility, explicit interfaces, dependency inversion with clear constructor injection or settings objects.

Fail loudly with helpful errors and actionable messages.

No secrets in repo: use env vars, Ansible Vault, Jenkins creds; never hardcode.

Idempotency: scripts/playbooks can be run repeatedly.

Validation is mandatory: every task ends with a verification step.

Directory & File Standards
Keep repo-root canonical and paths relative to /opt/HX-Infrastructure-.

Prefer these locations:

api-gateway/ – FastAPI app (main.py, config.py, requirements.lock), docs, systemd notes.

llm-01/, llm-02/ – node-specific scripts/config under scripts/, config/ollama/, services/.

orc/ – orchestration/embeddings node resources.

lib/ – shared shell helpers (e.g., model-config.sh).

scripts/ – repo-wide utilities (Python/Bash).

.github/ – workflows, Copilot guidance, templates.

Use kebab-case for file/dir names (except Python modules, which are snake_case).

Coding Standards
Python (API Gateway & tools):

Python 3.12; type hints required; pydantic v2+.

Logging via logging with structured context; no print() in services.

HTTP calls via httpx with appropriate timeouts. Implement retries carefully: apply them to idempotent methods (GET, PUT, DELETE) or on specific connection errors. Avoid automatically retrying POST requests to prevent duplicate processing.

Separate config in config.py with pydantic-settings; do not import .env directly.

Bash:

set -Eeuo pipefail; explicit exits and trap on error.

Check directories exist before creation; check files before writing.

Emit clear success messages; sleep 5s when starting/stopping services to verify state.

Ansible:

Use roles; check_mode support where possible; handlers for service restarts.

Templates for configs; no inline heredocs in tasks unless temporary scaffolding.

Service Management Requirements
When Copilot generates service commands (systemd or manual), always:

Execute the action.

sleep 5 seconds.

Print a success confirmation, e.g., echo "Ollama started successfully!".
Example (manual fallback):

Bash

nohup ollama serve >/var/log/ollama/ollama.out 2>&1 &
sleep 5
pgrep -x ollama >/dev/null && echo "Ollama started successfully!" || { echo "Ollama failed to start"; exit 1; }
API Gateway (FastAPI) Guidelines
Endpoints:

/healthz – returns {"status":"ok"}

/v1/models – list mapped model IDs from config.

/v1/chat/completions – OpenAI-compatible streaming with StreamingResponse.

Config:

OLLAMA_BASE_URL or per-model mapping via env + config.py.

Timeouts and backoff for upstream calls.

Streaming:

NDJSON or SSE-like chunks; do not buffer entire responses in memory.

Ollama & Models
Target port: 11434; remote hosts via OLLAMA_HOST/base URL in gateway config.

Prefer quantization and model variants explicitly by ID (e.g., mixtral:8x7b-instruct-q5_K_M when relevant).

Model pulls should be scripted with validation (hash/size check if available).

Security & Compliance
No secrets, tokens, or passwords committed. Example placeholders:

POSTGRES_PASSWORD → use Ansible Vault / Jenkins credentials.

Use umask 027 for generated files; restrict perms on /etc/* configs to root:root, 0640 unless service requires otherwise.

TLS handled at edge (gateway or reverse proxy); services should support being behind TLS.

CI/CD Expectations
Jenkins pipelines must:

Lint (YAML, Python), run --syntax-check for Ansible.

Gate deploy steps behind manual approvals when touching prod.

Archive logs/artifacts outside the repo; never commit runtime logs.

Documentation & Examples
Provide example blocks for:

Ansible task with validation step.

FastAPI endpoint with streaming.

Bash service control snippet (start/stop with 5s wait and success echo).

Example — Ansible task (idempotent with validation)
YAML

- name: Ensure ollama service is started
  service:
    name: ollama
    state: started
    enabled: true
  register: ollama_service

- name: Validate ollama is responding
  uri:
    url: "http://localhost:11434/api/tags"
    method: GET
    status_code: 200
  register: ollama_health
  retries: 3
  delay: 5
  until: ollama_health.status == 200
Example — FastAPI streaming proxy (sketch)
Python

@app.post("/v1/chat/completions")
async def chat(req: ChatCompletionRequest):
    async with httpx.AsyncClient(timeout=HTTPX_TIMEOUT) as client:
        upstream = client.stream("POST", f"{cfg.ollama}/v1/chat/completions", json=req.model_dump())
        return StreamingResponse((await upstream).__aiter__(), media_type="application/json")
Copilot “Do / Don’t”
Do: generate explicit, validated steps; use our directory standards; include final checks.

Do: favor composable helpers over monoliths; keep functions short with types.

Don’t: assume local paths outside /opt/HX-Infrastructure-; never suggest committing secrets/logs.

Don’t: create multiple services for each model—Ollama is single-port, multi-model.

Review Checklist (for PR templates/workflows)
No secrets or logs committed; .gitignore respected.

Validation steps included for new tasks/services.

Paths use /opt/HX-Infrastructure- (no references to Dev-Test).

Configurable via env; defaults safe; errors actionable.

Streaming endpoints tested without buffering entire response.