#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="/opt/hx-infrastructure/llm-01"
REPO_DIR="/opt/hx-infrastructure"   # Adjust if repository root differs
cd "$REPO_DIR"

# Safety: ensure Git is configured (no-op if already set)
git config user.name  "HX-Automation" || true
git config user.email "automation@hana-x.ai" || true

# Add and commit only the llm-01 README
git add llm-01/README.md || true
git commit -m "docs(llm-01): update README $(date -Is)" || true
echo "README sync attempted. Review 'git status' for details."
