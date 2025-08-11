#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="/opt/hx-infrastructure/llm-01"
TPL="$ROOT/config/readme/template.md.j2"
OUT="$ROOT/README.md"

# Collect simple facts (extend later)
NVME_DEV="/dev/nvme1n1p1"
SATA_DEV="/dev/sda1"
MODELS_MNT="/opt/hx-infrastructure/llm-01/models"
BULK_MNT="/opt/hx-infrastructure/llm-01/data/llm_bulk_storage"
OLLAMA_STATUS="$(systemctl is-active ollama 2>/dev/null || true)"

# Minimal render (placeholder): emit key facts into README until Jinja renderer is wired
{
  echo "# hx-llm-server-01 — LLM Server Overview"
  echo ""
  echo "**Generated:** $(date -Is)"
  echo ""
  echo "## Storage Mapping"
  echo "- NVMe Device: ${NVME_DEV}"
  echo "- SATA Device: ${SATA_DEV}"
  echo "- Models Mount: ${MODELS_MNT}"
  echo "- Bulk Storage Mount: ${BULK_MNT}"
  echo ""
  echo "## Services"
  echo "- Ollama: ${OLLAMA_STATUS}"
  echo "- Node Exporter: ${ROOT}/services/metrics/node-exporter"
  echo ""
  echo "## Validation Summary"
  echo "- Last Health Check: (tbd)"
  echo "- Smoke Tests: (tbd)"
} > "$OUT"

echo "README rendered to $OUT"
