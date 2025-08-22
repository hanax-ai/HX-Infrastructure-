# Engineering Task: Register RAG Upsert Router in App Factory

> **Task ID**: `ENG-004`  
> **Priority**: `High`  
> **Assigned To**: `Infrastructure Team`  
> **Due Date**: `2025-08-21`

---

## 🎯 Objective

Register the RAG upsert router in the FastAPI application factory, making the new endpoint available through the gateway service while maintaining proper application structure.

---

## 🏗️ Infrastructure Context

- **Component**: `api-gateway`
- **Service Impact**: `hx-gateway-ml.service (port 4010)`
- **Network Changes**: `No`
- **Rollback Plan**: `Remove router registration from app.py and restart service`

---

## ⚠️ Risk Assessment

- **Risk Level**: `Medium`
- **Potential Impact**: Service restart required, potential API disruption if registration fails
- **Mitigation**: Test router import before registration, have rollback plan ready
- **Dependencies**: ENG-001, ENG-002, and ENG-003 must be completed first

---

## ✅ Execution Plan

### Step 0: Verify Preconditions/Pre-Flight

*Ensure all necessary environment permissions, directories, files, variables, configurations, and database migrations are in place before starting.*

1. **Verify all previous modules exist** *(Est: 0.1 hours)*
   - Check models, services, and routes modules are available
   - Verify they can be imported successfully
2. **Locate app factory file** *(Est: 0.1 hours)*
   - Find main app.py or application factory file
   - Review existing router registration patterns
3. **Test router import** *(Est: 0.1 hours)*
   - Verify new router can be imported without errors
   - Check for any circular import issues

### Implementation Steps

1. **Backup current app configuration** *(Est: 0.1 hours)*

   ```bash
   sudo cp /opt/HX-Infrastructure-/api-gateway/gateway/src/app.py /opt/HX-Infrastructure-/api-gateway/gateway/src/app.py.backup
   ```

2. **Add router import to app.py** *(Est: 0.2 hours)*
   - Add import statement for RAG upsert router
   - Follow existing import patterns
   - Verify no import conflicts

3. **Register router in application factory** *(Est: 0.3 hours)*
   - Add router registration with appropriate prefix
   - Include proper tags for OpenAPI grouping
   - Follow existing router registration patterns

4. **Validate application startup** *(Est: 0.2 hours)*
   - Test application can start without errors
   - Verify all existing routes still work
   - Check new routes are properly registered

---

## 🧪 Validation Criteria

### Must-Pass Validations

1. **Service Health**: Gateway service can start and remain operational
2. **End-to-End**: App can import all routers and start successfully  
3. **Performance**: No impact on existing functionality
4. **Security**: Router registration doesn't expose unintended endpoints

### Test Case

- **Description**: Register RAG upsert router in FastAPI app and verify successful integration
- **Expected Result**: App starts successfully with new router registered and accessible

### Test Steps

1. Verify app.py was modified correctly
2. Test application startup without errors
3. Validate new router is accessible
4. Check existing functionality remains intact

### Test Commands

```bash
# Verify app.py modification
grep -n "rag_upsert" /opt/HX-Infrastructure-/api-gateway/gateway/src/app.py

# Test application startup (dry run)
cd /opt/HX-Infrastructure-/api-gateway/gateway && python -c "
from src.app import create_app
app = create_app()
print('✅ App created successfully')
print(f'✅ App has {len(app.routes)} total routes')
"

# Check router registration
cd /opt/HX-Infrastructure-/api-gateway/gateway && python -c "
from src.app import create_app
app = create_app()
upsert_routes = [r for r in app.routes if 'upsert' in str(r.path)]
print(f'✅ Found {len(upsert_routes)} upsert routes')
for route in upsert_routes:
    print(f'  - {route.methods} {route.path}')
"

# Verify module imports work
python -m pyflakes /opt/HX-Infrastructure-/api-gateway/gateway/src/app.py
```

---

## 📊 Status Tracking

- **Current Status**: `Not Started`
- **Completion**: `0%`
- **Time Estimated**: `0.9 hours`
- **Time Actual**: `[To be filled]`
- **Last Updated**: `2025-08-21`
- **Blocked By**: `ENG-001 (Models), ENG-002 (Services), ENG-003 (Routes)`

### Change Log

- **2025-08-21**: Task created based on SOLID-compliant RAG upsert requirements

---

## 📎 Additional Information

### Requirements

- All previous modules (ENG-001, ENG-002, ENG-003) must be completed first
- App factory pattern must be maintained
- Router registration should follow existing patterns
- No disruption to existing API endpoints

### Notes

- This task integrates all previous work into the running application
- Service restart will be required in the next task
- Router will be accessible at `/v1/rag/upsert` prefix

---

## 📚 References

- **Related Issues**: RAG Document Upsert Endpoint Implementation
- **Documentation**: `/opt/HX-Infrastructure-/api-gateway/x-Tasks/RAG-Document-Upsert-Endpoint-Tasks/RAG-Doc-Upsert-2.md`
- **Architecture Notes**: FastAPI application factory pattern with modular router registration
- **Dependencies**: Requires ENG-001, ENG-002, ENG-003 completion, blocks ENG-005 (Service Restart)
