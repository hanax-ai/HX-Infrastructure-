# Engineering Task: Restart and Verify Gateway Service

> **Task ID**: `RAG-003`  
> **Priority**: `High`  
> **Assigned To**: `[Team Member]`  
> **Due Date**: `[YYYY-MM-DD]`

---

## 🎯 Objective
To restart the gateway service to activate the new `/v1/rag/search` endpoint and verify that the service starts up successfully with the new configuration.

---

## ✅ Execution Plan

### Step 0: Verify Preconditions
*Ensure Task `RAG-002` is complete. You must have `sudo` privileges.*

1.  **Stop the Gateway Service**
    - Perform a clean stop of the service.
    ```bash
    echo "Stopping HX LiteLLM Gateway..."
    sudo systemctl stop hx-litellm-gateway
    sleep 5
    if ! sudo systemctl is-active --quiet hx-litellm-gateway; then
      echo "HX Gateway stopped successfully!"
    else
      echo "ERROR: HX Gateway failed to stop." >&2; exit 1
    fi
    ```
2.  **Start the Gateway Service**
    - Start the service with the new RAG endpoint enabled.
    ```bash
    echo "Starting HX LiteLLM Gateway with RAG endpoint enabled..."
    sudo systemctl start hx-litellm-gateway
    sleep 5
    if sudo systemctl is-active --quiet hx-litellm-gateway; then
      echo "HX Gateway started successfully!"
    else
      echo "ERROR: HX Gateway failed to start." >&2
      journalctl -u hx-litellm-gateway -n 200 --no-pager
      exit 1
    fi
    ```

---

## 🧪 Validation Criteria

### Test Case
- **Description**: Confirm that the `hx-litellm-gateway` service is running after being restarted with the new configuration.
- **Expected Result**: The `systemctl is-active` command should return a success status (exit code 0).

### Test Steps
1.  **Check Service Status**
    ```bash
    sudo systemctl is-active --quiet hx-litellm-gateway && echo "✅ Service is active." || echo "❌ Service failed to start."
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
- If the service fails to start, use `sudo journalctl -u hx-litellm-gateway -n 200 --no-pager` to check the logs for errors.
