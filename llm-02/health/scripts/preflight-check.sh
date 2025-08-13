#!/bin/bash
set -euo pipefail

echo "=== [HX llm-02] Preflight checks ==="

echo "[GPU] NVIDIA driver:"
if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "ERROR: nvidia-smi not found. Fix GPU/driver/container runtime." >&2
  exit 1
fi
if command -v timeout >/dev/null 2>&1; then
  timeout 5s nvidia-smi
else
  nvidia-smi
fi || { echo "ERROR: nvidia-smi failed or hung. Fix GPU/driver first." >&2; exit 1; }

echo "[CUDA] Toolchain (optional):"
if command -v nvcc &>/dev/null; then nvcc --version; else echo "nvcc not found (ok if not required for Ollama)."; fi

MODEL_STORE_PATH="${MODEL_STORE_PATH:-/mnt/active_llm_models}"
echo "[DISK] Model store path: $MODEL_STORE_PATH (create if missing):"
if [ ! -d "$MODEL_STORE_PATH" ]; then
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    mkdir -p "$MODEL_STORE_PATH"
  elif command -v sudo >/dev/null 2>&1; then
    sudo mkdir -p "$MODEL_STORE_PATH"
  else
    echo "ERROR: Need root to create $MODEL_STORE_PATH but sudo is not available." >&2
    exit 1
  fi
  echo "Created $MODEL_STORE_PATH"
fi
if [ ! -w "$MODEL_STORE_PATH" ]; then
  echo "ERROR: $MODEL_STORE_PATH is not writable by $(id -un)." >&2
  exit 1
fi
df -h "$MODEL_STORE_PATH" || true
# Optional: warn if low space (override with REQUIRED_FREE_GB)
required_gb="${REQUIRED_FREE_GB:-20}"
avail_kb="$(df -Pk "$MODEL_STORE_PATH" | awk 'NR==2{print $4}')"
avail_gb="$((avail_kb/1024/1024))"
if (( avail_gb < required_gb )); then
  echo "WARN: Only ${avail_gb}GiB free at $MODEL_STORE_PATH (recommended >= ${required_gb}GiB)."
fi

PORT="${OLLAMA_PORT:-11434}"
echo "[PORT] $PORT availability (expected free before start):"
if command -v ss >/dev/null 2>&1; then
  if ss -ltn | awk -v p=":$PORT" '$4 ~ p {found=1} END{exit !found}'; then
    echo "WARN: Port $PORT already in use (ensure no conflicting service)."
  else
    echo "OK: Port $PORT free."
  fi
elif command -v lsof >/dev/null 2>&1; then
  if lsof -iTCP:"$PORT" -sTCP:LISTEN -Pn >/dev/null 2>&1; then
    echo "WARN: Port $PORT already in use (ensure no conflicting service)."
  else
    echo "OK: Port $PORT free."
  fi
else
  echo "INFO: Neither 'ss' nor 'lsof' is available; skipping port check."
fi

echo "=== Preflight complete ==="
