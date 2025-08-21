# Engineering Task Template

## Task Information
**Task ID:** ENG-010  
**Task Title:** Document and Verify Rollback Procedure
**Priority:** Low  
**Assigned To:** Platform/Ops  
**Due Date:** 2025-09-04

---

## Execution Steps
1.  Add a "Rollback Procedure" section to the `/opt/HX-Infrastructure-/api-gateway/docs/systemd-service.md` or a relevant operational guide.
2.  Document the steps to revert to the previous `ExecStart` command, which ran the LiteLLM CLI directly.
    ```ini
    # To roll back, edit the systemd drop-in:
    # sudo systemctl edit hx-gateway-ml
    #
    # Replace the ExecStart with the previous version:
    [Service]
    ExecStart=
    ExecStart=/opt/HX-Infrastructure-/api-gateway/gateway/venv/bin/litellm --config /path/to/your/config.yaml --port 4010
    
    # Then, reload and restart:
    # sudo systemctl daemon-reload
    # sudo systemctl restart hx-gateway-ml
    ```
3.  Verify that the documented procedure works as expected in a staging environment.

---

## Validation Test
**Test Description:** Confirm that the documented rollback procedure successfully reverts the service to its previous, non-pipeline entrypoint.  
**Expected Result:** The service becomes active and responds to health checks using the old entrypoint.

### Test Steps
1.  Execute the documented rollback commands.
2.  Check that the service is active: `sudo systemctl is-active hx-gateway-ml` (Expected: `active`).
3.  Perform a health check to ensure the old service is running:
    `curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer sk-hx-dev-default" http://127.0.0.1:4010/health` (Note: endpoint might be `/health`, not `/healthz`).

---

## Status Tracking
**Current Status:** Not Started  
**Completion Percentage:** 0%  
**Last Updated:** 2025-08-21  

### Change Log
- 2025-08-21 - Task created.

---

## Additional Requirements
- The exact previous `ExecStart` command should be retrieved from version control or backups to ensure accuracy.

---

## Notes
- This documentation is crucial for operational stability, providing a quick and tested way to revert in case of unforeseen issues with the new `GatewayPipeline`.
