# Engineering Task: Confirm RAG Feature Rollback Procedure

> **Task ID**: `RAG-005`  
> **Priority**: `Medium`  
> **Assigned To**: `[Team Member]`  
> **Due Date**: `[YYYY-MM-DD]`

---

## 🎯 Objective
To document and confirm the procedure for safely disabling the RAG feature via its feature flag, providing a rapid rollback path without requiring a code redeployment.

---

## ✅ Execution Plan

### Step 0: Verify Preconditions
*This procedure is typically executed only if validation fails in Task `RAG-004`.*

1.  **Disable Feature Flag**
    - Edit the `systemd` override file for the gateway service.
    ```bash
    sudo systemctl edit hx-litellm-gateway
    ```
    - Change the `Environment` directive from `true` to `false`.
    ```ini
    [Service]
    Environment="ENABLE_RAG=false"
    ```
2.  **Reload and Restart**
    - Apply the `systemd` change and restart the service.
    ```bash
    sudo systemctl daemon-reload
    sudo systemctl restart hx-litellm-gateway
    sleep 5
    ```

---

## 🧪 Validation Criteria

### Test Case
- **Description**: Verify that the service restarts successfully and the `/v1/rag/search` endpoint is no longer available (returns a 404 Not Found).
- **Expected Result**: The service is active and a `curl` command to the RAG endpoint results in an HTTP 404 status.

### Test Steps
1.  **Confirm Service is Active**
    ```bash
    sudo systemctl is-active --quiet hx-litellm-gateway && echo "✅ Service reverted successfully."
    ```
2.  **Confirm Endpoint is Disabled**
    ```bash
    AUTH_HEADER="Authorization: Bearer sk-mDyhCELJX..." # Use a valid key
    BASE_URL="http://127.0.0.1:4000"
    STATUS_ROLLBACK=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" -H "Content-Type: application/json" -d '{"query":"test"}' "$BASE_URL/v1/rag/search")
    [ "$STATUS_ROLLBACK" -eq 404 ] && echo "✅ Rollback Validated: RAG endpoint is disabled (404 Not Found)." || echo "❌ Rollback Failed (Status: $STATUS_ROLLBACK)"
    ```

---

## 📊 Status Tracking

- **Current Status**: `Not Started`
- **Completion**: `0%`
- **Last Updated**: `2025-08-21`

### Change Log
- **2025-08-21**: Task created from `rag-search-overview.md`.

---

## 📎 Additional Information

### Notes
- This procedure provides a fast and safe way to disable the feature in case of unexpected issues in production.
