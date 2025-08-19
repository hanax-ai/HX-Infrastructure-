#!/usr/bin/env bash
set -euo pipefail

if ! command -v ollama >/dev/null 2>&1; then
  echo "ollama not available; skip verification."
  exit 0
fi

# Show headers and the first data row with field counts
# Capture ollama list output to check for data rows
ollama_output=$(ollama list)
echo "$ollama_output" | awk '
NR==1 {
  print "HEADER:", $0
  next
}
NR==2 {
  print "ROW:", $0
  for (i=1; i<=NF; i++) printf("  $" i "=%s\n", $i)
  has_data = 1
}
END {
  if (!has_data) {
    print "No data rows; only header present"
  }
}'
