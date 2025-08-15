#!/usr/bin/env bash
set -euo pipefail

# Usage: ./emb-external-verify.sh <ORC_HOST> [PORT] [MODELS...]
# Example: ./emb-external-verify.sh 192.168.10.30 11434 mxbai-embed-large nomic-embed-text all-minilm

HOST="${1:-}"; PORT="${2:-11434}"; shift || true; shift || true
if [ -z "${HOST}" ]; then echo "Usage: $0 <ORC_HOST> [PORT] [MODELS...]"; exit 2; fi
MODELS=("$@"); if [ ${#MODELS[@]} -eq 0 ]; then MODELS=(mxbai-embed-large nomic-embed-text all-minilm); fi

# Expected dims (adjust here if you swap models)
expect_dim() {
  case "$1" in
    mxbai-embed-large) echo 1024 ;;
    nomic-embed-text)  echo 768  ;;
    all-minilm)        echo 384  ;;
    *) echo 0 ;;
  esac
}

A="HX-Infrastructure validates embeddings."
B="HX-Infrastructure validates the embedding system."
C="This sentence is unrelated to infrastructure."

CSV="external_emb_check.csv"
if [ ! -f "$CSV" ]; then
  echo "timestamp,host,port,model,latency_ms,dimension,cosAB,cosAC,pass" > "$CSV"
fi

echo "=== External verify against http://${HOST}:${PORT} ==="

# API reachability
ver=$(curl -fsS --max-time 10 "http://${HOST}:${PORT}/api/version" | jq -r .version)
echo "[API] version: ${ver}"

pass_all=1

for M in "${MODELS[@]}"; do
  echo "[MODEL] $M"

  # Time A
  t0=$(date +%s%N)
  EA=$(curl -fsS -X POST "http://${HOST}:${PORT}/api/embeddings" -H "Content-Type: application/json" -d "{\"model\":\"$M\",\"input\":\"$A\"}")
  t1=$(date +%s%N); msA=$(( (t1 - t0)/1000000 ))

  EB=$(curl -fsS -X POST "http://${HOST}:${PORT}/api/embeddings" -H "Content-Type: application/json" -d "{\"model\":\"$M\",\"input\":\"$B\"}")
  EC=$(curl -fsS -X POST "http://${HOST}:${PORT}/api/embeddings" -H "Content-Type: application/json" -d "{\"model\":\"$M\",\"input\":\"$C\"}")

  VA=$(echo "$EA" | jq -r '.embedding // (.data[0].embedding)')
  VB=$(echo "$EB" | jq -r '.embedding // (.data[0].embedding)')
  VC=$(echo "$EC" | jq -r '.embedding // (.data[0].embedding)')

  dim=$(echo "$VA" | jq 'length')
  exp=$(expect_dim "$M")
  dim_ok="yes"; if [ "$exp" -gt 0 ] && [ "$dim" -ne "$exp" ]; then dim_ok="no"; fi

  read -r cosAB cosAC < <(python3 scripts/cosine_similarity.py "$VA" "$VB" "$VC")

  # Pass condition: dimension matches (if known) AND semantic sanity (A~B > A~C + 0.05)
  pass="OK"
  if [ "$dim_ok" != "yes" ]; then pass_all=0; pass="DIM_MISMATCH"; fi
  awk -v ab="$cosAB" -v ac="$cosAC" 'BEGIN{exit !(ab>ac+0.05)}' || { pass_all=0; pass="SEMANTIC_FAIL"; }

  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "$ts,$HOST,$PORT,$M,$msA,$dim,$cosAB,$cosAC,$pass" >> "$CSV"
  echo "  latency=${msA}ms  dim=${dim}  cosAB=${cosAB}  cosAC=${cosAC}  [$pass]"
done

if [ $pass_all -eq 1 ]; then
  echo "External access verification PASSED for all models."
  exit 0
else
  echo "External access verification FAILED for one or more models."
  exit 1
fi
