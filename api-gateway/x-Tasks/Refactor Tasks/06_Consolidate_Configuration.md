# Engineering Task Template

## Task Information
**Task ID:** ENG-006  
**Task Title:** Consolidate and Clean Up Configuration Files
**Priority:** Medium  
**Assigned To:** Platform/Ops  
**Due Date:** 2025-08-30

---

## Execution Steps
1.  Establish `/opt/HX-Infrastructure-/api-gateway/config/api-gateway/` as the single source of truth for all configuration.
2.  Move any essential files from `/opt/HX-Infrastructure-/api-gateway/gateway/config/` to the source-of-truth directory and delete the now-empty `gateway/config/` directory.
3.  Delete the redundant `/opt/HX-Infrastructure-/api-gateway/gateway/model_registry.yaml`.
4.  As a temporary measure for legacy scripts, create a symlink from the old `model_registry.yaml` location to the new one:
    `sudo ln -s /opt/HX-Infrastructure-/api-gateway/config/api-gateway/model_registry.yaml /opt/HX-Infrastructure-/api-gateway/gateway/model_registry.yaml`
5.  Audit all application code and scripts to ensure they reference the consolidated configuration paths.

---

## Validation Test
**Test Description:** Verify that the application runs correctly using only the consolidated configuration directory and that legacy paths resolve via symlinks.  
**Expected Result:** The service starts and is fully functional. Symlinks point to the correct target files.

### Test Steps
1.  Check that the symlink resolves correctly:
    `ls -l /opt/HX-Infrastructure-/api-gateway/gateway/model_registry.yaml` (Expected: Shows it is a symlink to the file in `config/api-gateway/`).
2.  Restart the service to ensure it reads the configuration from the correct location:
    `sudo systemctl restart hx-gateway-ml && sleep 5` (Expected: Service is `active`).
3.  Make an API call that depends on the `model_registry.yaml` to confirm it was loaded correctly.

---

## Status Tracking
**Current Status:** Not Started  
**Completion Percentage:** 0%  
**Last Updated:** 2025-08-21  

### Change Log
- 2025-08-21 - Task created.

---

## Additional Requirements
- A future task should be created to remove the reliance on symlinks by updating the scripts that use them.

---

## Notes
- Using Pydantic settings for configuration loading is the recommended next step but is not required for this task.
