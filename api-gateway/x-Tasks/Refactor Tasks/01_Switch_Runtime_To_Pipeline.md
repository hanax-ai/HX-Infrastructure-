# Engineering Task Template

## Task Information
**Task ID:** ENG-001  
**Task Title:** Switch Runtime to GatewayPipeline Entrypoint
**Priority:** High  
**Assigned To:** Platform/Ops  
**Due Date:** 2025-08-27

---

## Execution Steps
1.  Open the systemd service unit for editing: `sudo systemctl edit hx-gateway-ml`.
2.  In the drop-in editor, replace the `ExecStart` directive to point to the `build_app` factory in `gateway.src.app`.
    ```ini
    [Service]
    ExecStart=
    ExecStart=/opt/HX-Infrastructure-/api-gateway/gateway/venv/bin/uvicorn gateway.src.app:build_app --factory --host 0.0.0.0 --port 4010 --workers 1
    WorkingDirectory=/opt/HX-Infrastructure-/api-gateway/gateway
    ```
3.  Reload the systemd daemon to apply the changes: `sudo systemctl daemon-reload`.
4.  Restart the service and allow 5 seconds for it to initialize: `sudo systemctl restart hx-gateway-ml && sleep 5`.

---

## Validation Test
**Test Description:** Confirm that the `GatewayPipeline` application is live, listening on the correct port, and responding to basic health checks.  
**Expected Result:** The service is active, and health/model endpoints respond correctly (authentication may be required).

### Test Steps
1.  Check if the service is active: `sudo systemctl is-active hx-gateway-ml` (Expected: `active`).
2.  Verify the service is listening on port 4010: `ss -ltnp | grep ':4010'` (Expected: Shows a `LISTEN` state for the uvicorn process).
3.  Perform a health check: `curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:4010/healthz` (Expected: `200`).

---

## Status Tracking
**Current Status:** Not Started  
**Completion Percentage:** 0%  
**Last Updated:** 2025-08-21  

### Change Log
- 2025-08-21 - Task created.

---

## Additional Requirements
- The existing environment file (`db_cache.env`) loaded by the systemd unit must contain all necessary variables (DB_URL, REDIS_URL, etc.).

---

## Notes
- Keep the previous `ExecStart` line commented out in the drop-in file for a quick rollback if needed.
