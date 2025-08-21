# Engineering Task: Configure and Enable the RAG Feature

> **Task ID**: `RAG-002`  
> **Priority**: `High`  
> **Assigned To**: `[Team Member]`  
> **Due Date**: `[YYYY-MM-DD]`

---

## 🎯 Objective
To enable the new RAG search endpoint by setting the `ENABLE_RAG` feature flag within the `systemd` service configuration.

---

## ✅ Execution Plan

### Step 0: Verify Preconditions
*Ensure Task `RAG-001` is complete. You must have `sudo` privileges to edit `systemd` configuration.*

1.  **Create or Amend Systemd Override**
    - Use the `systemctl edit` command to create a configuration override for the gateway service. This is the recommended way to modify service definitions without altering the original service file.
    ```bash
    sudo systemctl edit hx-litellm-gateway
    ```
2.  **Set Environment Variable**
    - Inside the editor, add the `[Service]` section if it doesn't exist and add the `Environment` directive to enable the feature.
    ```ini
    [Service]
    Environment="ENABLE_RAG=true"
    ```

---

## 🧪 Validation Criteria

### Test Case
- **Description**: Verify that the `systemd` daemon has loaded the new environment variable for the service.
- **Expected Result**: The `systemctl show` command should display the `Environment="ENABLE_RAG=true"` line.

### Test Steps
1.  **Reload Systemd Daemon**
    - Apply the configuration changes by reloading the `systemd` daemon.
    ```bash
    sudo systemctl daemon-reload
    ```
2.  **Verify Service Configuration**
    - Use `systemctl show` and `grep` to confirm the environment variable is loaded.
    ```bash
    systemctl show hx-litellm-gateway | grep ENABLE_RAG
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
- This task enables the feature flag but does not make the endpoint live until the service is restarted (Task `RAG-003`).
