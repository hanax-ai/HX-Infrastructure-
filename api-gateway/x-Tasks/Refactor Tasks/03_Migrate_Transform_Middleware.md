# Engineering Task Template

## Task Information
**Task ID:** ENG-003  
**Task Title:** Migrate Request Transformation to TransformMiddleware
**Priority:** High  
**Assigned To:** Backend  
**Due Date:** 2025-08-28

---

## Execution Steps
1.  Locate the ad-hoc request body transformation logic for the `/v1/embeddings` endpoint within `/opt/HX-Infrastructure-/api-gateway/gateway/src/main.py`.
2.  Implement this logic in the `process` method of the `TransformMiddleware` in `/opt/HX-Infrastructure-/api-gateway/gateway/src/middlewares/transform.py`.
3.  The middleware should first check if the request path is `/v1/embeddings`. If not, it should pass the context to the next stage without modification.
4.  Ensure the transformation logic is idempotent (e.g., it only maps `prompt` to `input` if `prompt` exists and `input` does not).
5.  Register the `TransformMiddleware` in the `GatewayPipeline` after `ValidationMiddleware` but before `ExecutionMiddleware`.

---

## Validation Test
**Test Description:** Verify that requests to the `/v1/embeddings` endpoint are correctly transformed by the middleware, maintaining the same behavior from a client's perspective.  
**Expected Result:** A valid request to `/v1/embeddings` returns a `200 OK` response with the expected vector payload.

### Test Steps
1.  Send a valid request to the embeddings endpoint using the `prompt` field.
    ```bash
    curl -sS -H "Authorization: Bearer sk-hx-dev-default" -H "Content-Type: application/json" \
    -d '{"model":"text-embedding-ada-002","prompt":"hello"}' \
    http://127.0.0.1:4010/v1/embeddings | jq '.data[0].embedding | length'
    ```
    (Expected: A non-zero integer representing the vector length, e.g., `1536`).

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
- Adding a route guard is critical to prevent this middleware from accidentally modifying the body of unrelated POST/PUT requests.
