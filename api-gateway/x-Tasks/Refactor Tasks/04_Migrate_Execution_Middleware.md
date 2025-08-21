# Engineering Task Template

## Task Information
**Task ID:** ENG-004  
**Task Title:** Centralize Upstream Proxying in ExecutionMiddleware
**Priority:** Medium  
**Assigned To:** Backend  
**Due Date:** 2025-08-29

---

## Execution Steps
1.  Extract all upstream request forwarding logic from `/opt/HX-Infrastructure-/api-gateway/gateway/src/main.py`. This includes building the upstream URL, forwarding headers, and handling the `httpx` client call.
2.  Implement this logic within the `process` method of the `ExecutionMiddleware` in `/opt/HX-Infrastructure-/api-gateway/gateway/src/middlewares/execution.py`.
3.  This middleware should be the final stage in the pipeline and is responsible for creating the response that is sent back to the client.
4.  Implement robust error mapping for upstream failures, such as `httpx.ConnectError` or 5xx status codes, ensuring a consistent error response format.
5.  Ensure all necessary headers (e.g., for tracing, rate limiting) are correctly passed through.

---

## Validation Test
**Test Description:** Verify that core OpenAI-style endpoints are proxied correctly and that upstream errors are handled gracefully.  
**Expected Result:** The `/v1/models` and `/v1/chat/completions` endpoints behave identically to the previous implementation.

### Test Steps
1.  Make a request to the `/v1/models` endpoint and verify the response.
    ```bash
    curl -sS -H "Authorization: Bearer sk-hx-dev-default" http://127.0.0.1:4010/v1/models | jq
    ```
    (Expected: A JSON object with a `data` array of model objects).
2.  Make a request to the `/v1/chat/completions` endpoint and verify the response.
    (Expected: A successful chat completion response).

---

## Status Tracking
**Current Status:** Not Started  
**Completion Percentage:** 0%  
**Last Updated:** 2025-08-21  

### Change Log
- 2025-08-21 - Task created.

---

## Additional Requirements
- The middleware must have access to the upstream URL and any required authentication keys from the central configuration service.

---

## Notes
- This is the final step in migrating the core logic from the monolithic `main.py` file.
