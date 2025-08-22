# Engineering Task: Restart Gateway Service and Verify Deployment

> **Task ID**: `ENG-005`  
> **Priority**: `High`  
> **Assigned To**: `Infrastructure Team`  
> **Due Date**: `2025-08-21`

---

## 🎯 Objective

Restart the hx-gateway-ml service to load the new RAG upsert functionality and verify the deployment is successful with all endpoints operational.

---

## 🏗️ Infrastructure Context

- **Component**: `api-gateway`
- **Service Impact**: `hx-gateway-ml.service (port 4010) - RESTART REQUIRED`
- **Network Changes**: `No`
- **Rollback Plan**: `Restore app.py.backup and restart service`

---

## ⚠️ Risk Assessment

- **Risk Level**: `Medium`
- **Potential Impact**: Temporary service unavailability during restart
- **Mitigation**: Quick restart process, immediate health check validation
- **Dependencies**: All previous tasks (ENG-001 through ENG-004.5) must be completed

---

## ✅ Execution Plan

### Step 0: Verify Preconditions/Pre-Flight

*Ensure all necessary environment permissions, directories, files, variables, configurations, and database migrations are in place before starting.*

1. **Verify all modules are in place** *(Est: 0.1 hours)*
   - Check models, services, routes modules exist
   - Verify app.py has been updated with router registration
2. **Confirm service configuration** *(Est: 0.1 hours)*
   - Check systemd service file exists
   - Verify service user permissions
3. **Test application startup** *(Est: 0.1 hours)*
   - Dry run application creation
   - Verify no import or startup errors

### Implementation Steps

1. **Stop the gateway service** *(Est: 0.1 hours)*

   ```bash
   sudo systemctl stop hx-gateway-ml.service
   sleep 5
   sudo systemctl status hx-gateway-ml.service --no-pager
   ```

2. **Start the gateway service with enhanced validation** *(Est: 0.2 hours)*

   ```bash
   sudo systemctl restart hx-gateway-ml.service && sleep 5 && \
     systemctl --no-pager --full status hx-gateway-ml.service | sed -n '1,15p' && \
     echo "HX Gateway restarted successfully!"
   ```

3. **Verify service is running** *(Est: 0.2 hours)*
   - Check systemd status
   - Verify port 4010 is listening
   - Check service logs for errors

4. **Test basic health endpoint** *(Est: 0.1 hours)*
   - Hit health check endpoint
   - Verify service responds correctly
   - Check existing functionality works

---

## 🧪 Validation Criteria

### Must-Pass Validations

1. **Service Health**: Gateway service starts and runs without errors
2. **End-to-End**: All existing endpoints remain functional  
3. **Performance**: Service startup time within normal parameters
4. **Security**: No security issues introduced during restart

### Test Case

- **Description**: Restart gateway service and verify successful deployment with new functionality
- **Expected Result**: Service runs normally with both existing and new endpoints operational

### Test Steps

1. Verify service stops cleanly
2. Verify service starts successfully  
3. Test health endpoint responds
4. Check service logs for errors

### Test Commands

```bash
# Check service status
sudo systemctl is-active hx-gateway-ml.service

# Verify port is listening
sudo netstat -tlnp | grep :4010 || ss -tlnp | grep :4010

# Test health endpoint
curl -f http://localhost:4010/healthz || echo "❌ Health check failed"

# Check service logs for errors
sudo journalctl -u hx-gateway-ml.service --since="5 minutes ago" --no-pager | grep -i error

# Verify service started successfully message
sudo journalctl -u hx-gateway-ml.service --since="5 minutes ago" --no-pager | tail -10
```

---

## 📊 Status Tracking

- **Current Status**: `Not Started`
- **Completion**: `0%`
- **Time Estimated**: `0.6 hours`
- **Time Actual**: `[To be filled]`
- **Last Updated**: `2025-08-21`
- **Blocked By**: `ENG-004.5 (Environment Configuration)`

### Change Log

- **2025-08-21**: Task created based on SOLID-compliant RAG upsert requirements

---

## 📎 Additional Information

### Requirements

- All previous tasks (ENG-001 through ENG-004.5) must be completed
- Systemd service configuration must be correct
- Service user must have proper permissions
- Health endpoints must remain functional

### Notes

- Service restart will load new RAG upsert functionality
- Existing functionality must remain operational
- Any startup errors should trigger rollback to previous state

---

## 📚 References

- **Related Issues**: RAG Document Upsert Endpoint Implementation
- **Documentation**: `/opt/HX-Infrastructure-/api-gateway/x-Tasks/RAG-Document-Upsert-Endpoint-Tasks/RAG-Doc-Upsert-2.md`
- **Architecture Notes**: Service deployment and validation procedures
- **Dependencies**: Requires all previous tasks completion, blocks ENG-006 (OpenAPI Validation)
