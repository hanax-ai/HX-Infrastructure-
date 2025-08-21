# Engineering Task Template

## Task Information
**Task ID:** ENG-005  
**Task Title:** Deprecate Monolithic `main.py` File
**Priority:** High  
**Assigned To:** Backend  
**Due Date:** 2025-08-29

---

## Execution Steps
1.  After all logic has been migrated to the `GatewayPipeline` middleware, create a backup of the original file:
    `sudo cp -a /opt/HX-Infrastructure-/api-gateway/gateway/src/main.py /opt/HX-Infrastructure-/api-gateway/gateway/src/main.py.bak.$(date -u +%Y%m%dT%H%M%SZ)`
2.  Prepend a deprecation banner to the top of `/opt/HX-Infrastructure-/api-gateway/gateway/src/main.py`:
    `sudo sed -i '1i# DEPRECATED – All logic has been migrated into GatewayPipeline stages. This file is no longer in use.\n' /opt/HX-Infrastructure-/api-gateway/gateway/src/main.py`
3.  Grep the entire repository to ensure no runtime code or scripts reference `main.py`.
    `grep -r "main.py" /opt/HX-Infrastructure-/`

---

## Validation Test
**Test Description:** Ensure the `main.py` file is no longer used by the running service and is clearly marked as deprecated.  
**Expected Result:** The `uvicorn` process targets `gateway.src.app:build_app`, and no running process references `main.py`.

### Test Steps
1.  Check the systemd service definition to confirm the `ExecStart` command.
    `systemctl cat hx-gateway-ml | grep -i ExecStart` (Expected: Shows `uvicorn` pointing to `gateway.src.app:build_app`).
2.  Check for any running processes associated with `main.py`.
    `pgrep -af main.py` (Expected: No results).

---

## Status Tracking
**Current Status:** Not Started  
**Completion Percentage:** 0%  
**Last Updated:** 2025-08-21  

### Change Log
- 2025-08-21 - Task created.

---

## Additional Requirements
- None.

---

## Notes
- The file should be kept for a short period for reference during the transition, but it should be scheduled for deletion in a future cleanup task.
