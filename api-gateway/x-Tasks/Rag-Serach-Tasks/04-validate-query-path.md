# Engineering Task: Validate RAG Query Path

> **Task ID**: `RAG-004.1`  
> **Priority**: `High`  
> **Assigned To**: `[Team Member]`  
> **Due Date**: `[YYYY-MM-DD]`

---

## 🎯 Objective
To verify that the `/v1/rag/search` endpoint correctly handles authenticated requests using the `query` parameter and returns a successful response.

---

## ✅ Execution Plan

### Step 0: Verify Preconditions
*Ensure Task `RAG-003` is complete and the service is active. Obtain a valid user API key for testing.*

1.  **Execute Test**
    - Run the `curl` command to send a valid, authenticated request with a `query` payload.

---

## 🧪 Validation Criteria

### Test Case
- **Description**: An authenticated request to the RAG endpoint with a JSON payload containing a `query` and `limit` should succeed.
- **Expected Result**: The command should return an HTTP status code of `200 OK`.

### Test Steps
1.  **Run Validation Command**
    ```bash
    # --- Test Setup ---
    BASE_URL="http://127.0.0.1:4000"
    AUTH_HEADER="Authorization: Bearer sk-mDyhCELJX..." # Use a valid key

    # --- Test Execution ---
    echo "--- Testing Query Path (expects 200 OK) ---"
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "$AUTH_HEADER" -H "Content-Type: application/json" \
      -d '{"query":"hello world","limit":3}' \
      "$BASE_URL/v1/rag/search")
    [ "$STATUS" -eq 200 ] && echo "✅ PASSED" || echo "❌ FAILED (Status: $STATUS)"
    ```

---

## 📊 Status Tracking

- **Current Status**: `Not Started`
- **Completion**: `0%`
- **Last Updated**: `2025-08-21`

### Change Log
- **2025-08-21**: Task created.

---

## 📎 Additional Information

### Notes
- This test validates the primary success path for text-based RAG searches.
