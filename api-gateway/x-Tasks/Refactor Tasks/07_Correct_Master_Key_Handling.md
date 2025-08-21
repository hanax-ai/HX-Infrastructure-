# Engineering Task Template

## Task Information
**Task ID:** ENG-007  
**Task Title:** Correct Master Key Handling
**Priority:** High  
**Assigned To:** Platform/Ops  
**Due Date:** 2025-08-27

---

## Execution Steps
1.  Back up the main configuration file: `sudo cp -a /opt/HX-Infrastructure-/api-gateway/config/api-gateway/config.yaml /opt/HX-Infrastructure-/api-gateway/config/api-gateway/config.yaml.bak`
2.  Comment out the `master_key` line in the YAML configuration to ensure it does not override the environment variable:
    `sudo sed -i 's/^\([[:space:]]*master_key:.*\)/#\1/' /opt/HX-Infrastructure-/api-gateway/config/api-gateway/config.yaml`
3.  Verify that the systemd service unit for `hx-gateway-ml` correctly loads an environment file that provides the `MASTER_KEY` or `LITELLM_MASTER_KEY` variable.

---

## Validation Test
**Test Description:** Verify that master key authentication works correctly using the key from the environment variable, not the (now-commented) YAML file.  
**Expected Result:** Admin-level endpoints accept the environment-provided key and return a `200 OK` status.

### Test Steps
1.  Restart the gateway service to ensure the new configuration is loaded:
    `sudo systemctl restart hx-gateway-ml && sleep 5`
2.  Perform a health check using the master key defined in the environment file:
    `curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer sk-hx-dev-default" http://127.0.0.1:4010/healthz` (Expected: `200`).

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
- This change prevents the less-secure practice of storing secrets in version-controlled YAML files and gives precedence to environment variables, which is a security best practice.
