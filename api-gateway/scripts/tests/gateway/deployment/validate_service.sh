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

echo "→ Clearing any previous failed state..."
sudo systemctl reset-failed "$SVC" 2>/dev/null || true

echo "→ Restarting service for validation..."
if sudo systemctl restart "$SVC"; then
    echo "   Service restart command succeeded"
else
    echo "❌ Service restart command failed"
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
    SYSTEMD_PAGER=cat sudo systemctl status "$SVC" --no-pager | sed -E 's/(HX_MASTER_KEY|Bearer [A-Za-z0-9_-]+|[Aa]pi[Kk]ey[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{8,})/[REDACTED]/g'
    exit 1
fi

echo "→ Checking service exit status..."
if sudo systemctl show "$SVC" --property=ExecMainStatus --value | grep -q "^0$"; then
    echo "✅ Service completed successfully (exit code 0)"
else
    echo "❌ Service failed with non-zero exit code"
    echo "Recent logs:"
    SYSTEMD_PAGER=cat sudo journalctl -u "$SVC" -n 200 -o cat --no-pager | sed -E 's/(HX_MASTER_KEY|Bearer [A-Za-z0-9_-]+|[Aa]pi[Kk]ey[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{8,})/[REDACTED]/g'
    exit 1
fi

echo "→ Showing test results summary..."

# Capture journalctl output and check for errors (avoid masking exit code with assignment)
tmp_journal="$(mktemp)"
trap 'rm -f "$tmp_journal"' EXIT
# shellcheck disable=SC2024
sudo journalctl -u "$SVC" --no-pager -n 200 -o cat >"$tmp_journal" 2>&1
journalctl_exit_code=$?
if [[ $journalctl_exit_code -ne 0 ]]; then
    echo "❌ ERROR: Failed to retrieve service logs via journalctl (exit code: $journalctl_exit_code)"
    echo "Raw journalctl output:"
    cat "$tmp_journal"
    rm -f "$tmp_journal"
    exit 1
fi
test_results="$(cat "$tmp_journal")"
rm -f "$tmp_journal"

# Filter for test results and handle empty results gracefully
filtered_results=$(echo "$test_results" | grep -E "(Test Suite Results|SUCCESS|FAIL|PASS|ERROR)" | tail -20)
if [[ -n "$filtered_results" ]]; then
    echo "$filtered_results"
else
    echo "No matching test result lines found in recent logs"
fi

echo "✅ Service validation completed successfully"
