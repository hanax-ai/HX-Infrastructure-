#!/usr/bin/env bash
set -euo pipefail

# SOLID: Single Responsibility - ONLY orchestrates deployment components
# Open/Closed Principle: Easy to add new steps without modifying existing ones

echo "=== [SOLID Deployment Orchestrator] Gateway Smoke Test Setup ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define deployment steps (SOLID: Open/Closed - easy to extend)
declare -a deployment_steps=(
    "create_config.sh"
    "create_orchestration.sh" 
    "set_permissions.sh"
    "update_systemd.sh"
    "validate_service.sh"
)

echo "Deployment steps: ${#deployment_steps[@]}"
echo

# Execute each step (SOLID: Single Responsibility per step)
failed_steps=0

for step in "${deployment_steps[@]}"; do
    step_script="${SCRIPT_DIR}/${step}"
    
    echo "==== Step: ${step} ===="
    
    if [[ ! -f "$step_script" ]]; then
        echo "❌ Step script not found: $step_script"
        ((failed_steps++))
        continue
    fi
    
    if [[ ! -x "$step_script" ]]; then
        chmod +x "$step_script"
    fi
    
    if "$step_script"; then
        echo "✅ Step completed: ${step}"
    else
        echo "❌ Step failed: ${step}"
        ((failed_steps++))
    fi
    
    echo
done

# Final results
echo "=== Deployment Results ==="
echo "Total Steps: ${#deployment_steps[@]}"
echo "Failed Steps: $failed_steps"

# Calculate success rate safely
count=${#deployment_steps[@]}
if [[ $count -gt 0 ]]; then
    echo "Success Rate: $(( (count - failed_steps) * 100 / count ))%"
else
    echo "Success Rate: N/A"
fi

if [[ $failed_steps -eq 0 ]]; then
    echo "🎉 SOLID Deployment Completed Successfully ✅"
    echo
    echo "Next steps:"
    echo "  - Manual test: sudo systemctl start hx-gateway-smoke.service"
    echo "  - Check timer: systemctl list-timers hx-gateway-smoke.timer"
    echo "  - View logs: journalctl -u hx-gateway-smoke.service"
    exit 0
else
    echo "⚠️  Some deployment steps failed"
    exit 1
fi
