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
    sudo systemctl edit hx-gateway-ml
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
    sudo systemctl restart hx-gateway-ml
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
    sudo systemctl is-active --quiet hx-gateway-ml && echo "✅ Service reverted successfully."
    ```
2.  **Confirm Endpoint is Disabled**
    ```bash
    # --- Test Setup ---
    # Ensure API_KEY and BASE_URL are set in your environment
    # Example:
    # export API_KEY="your-secret-api-key"
    # export BASE_URL="http://127.0.0.1:4000"
    AUTH_HEADER="Authorization: Bearer ${API_KEY}"
    BASE_URL="${BASE_URL:-http://127.0.0.1:4000}"

    # --- Test Execution ---
    STATUS_ROLLBACK=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" -H "Content-Type: application/json" -d '{"query":"test"}' "$BASE_URL/v1/rag/search")
    
    # --- Validation ---
    if [ "$STATUS_ROLLBACK" -eq 404 ] || [ "$STATUS_ROLLBACK" -eq 403 ]; then
      echo "✅ Rollback Validated: RAG endpoint is disabled (Status: $STATUS_ROLLBACK)."
    else
      echo "❌ Rollback Failed (Status: $STATUS_ROLLBACK)"
    fi
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
