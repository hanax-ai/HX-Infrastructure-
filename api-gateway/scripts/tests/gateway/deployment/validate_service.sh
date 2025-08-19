#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY validates service execution
echo "=== [Service Validator] Testing Systemd Service ==="

SVC="hx-gateway-smoke.service"

# Preflight check
if ! sudo systemctl cat "$SVC" >/dev/null 2>&1; then
    echo "❌ Service not found: $SVC"
    exit 1
fi

echo "→ Starting service for validation..."
if sudo systemctl start "$SVC"; then
    echo "   Service start command succeeded"
else
    echo "❌ Service start command failed"
    exit 1
fi

echo "→ Waiting for service completion (max 60 seconds)..."
timeout_reached=false
for i in {1..60}; do
    if ! sudo systemctl is-active --quiet "$SVC"; then
        echo "Service became inactive after $i seconds"
        break
    fi
    sleep 1
    if [[ $i -eq 60 ]]; then
        timeout_reached=true
    fi
done

if [[ "$timeout_reached" == "true" ]]; then
    echo "❌ Timed out waiting for $SVC to complete"
    echo "Service is still active after 60 seconds"
    sudo systemctl status "$SVC" --no-pager
    exit 1
fi

echo "→ Checking service exit status..."
if sudo systemctl show "$SVC" --property=ExecMainStatus --value | grep -q "^0$"; then
    echo "✅ Service completed successfully (exit code 0)"
else
    echo "❌ Service failed with non-zero exit code"
    echo "Recent logs:"
    sudo journalctl -u "$SVC" -n 10 --no-pager
    exit 1
fi

echo "→ Showing test results summary..."

# Capture journalctl output and check for errors
# Capture journalctl output and check for errors (avoid masking exit code with assignment)
tmp_journal="$(mktemp)"
if ! sudo journalctl -u "$SVC" --no-pager -n 200 -o cat >"$tmp_journal" 2>&1; then
    journalctl_exit_code=$?
    echo "❌ ERROR: Failed to retrieve service logs via journalctl (exit code: $journalctl_exit_code)"
    echo "Raw journalctl output:"
    cat "$tmp_journal"
    rm -f "$tmp_journal"
    exit 1
fi
test_results="$(cat "$tmp_journal")"
rm -f "$tmp_journal"

# Filter for test results and handle empty results gracefully
filtered_results=$(echo "$test_results" | grep -E "(✅|❌|Test Suite Results|SUCCESS|FAIL)" | tail -20)
if [[ -n "$filtered_results" ]]; then
    echo "$filtered_results"
else
    echo "No matching test result lines found in recent logs"
fi

echo "✅ Service validation completed successfully"
