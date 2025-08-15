# Ollama Embeddings API Compatibility Analysis

**Date**: August 14, 2025  
**Server**: hx-orc-server  
**Component**: Ollama Embeddings API  
**Issue**: Parameter compatibility for embedding requests  

## Issue Summary

The Ollama embeddings API currently only accepts the `prompt` parameter for text input, but many embedding APIs and clients expect the `input` parameter format.

## Test Results

### Current API Behavior

| Parameter | Status | Example | Result |
|-----------|--------|---------|---------|
| `prompt` | ✅ **WORKS** | `{"model":"mxbai-embed-large","prompt":"test"}` | 1024-dim vector |
| `input` | ❌ **FAILS** | `{"model":"mxbai-embed-large","input":"test"}` | **FAILURE MODE**: Empty array `[]` (not valid embedding) |

**Important**: The empty array response for `input` parameter is a failure mode, not a valid zero-length embedding. 

### Recommended Error Handling

When `input` parameter is used or empty, the server/proxy MUST validate and return HTTP 400 with clear error response:

```http
HTTP/1.1 400 Bad Request
Content-Type: application/json

{
  "error": "empty input parameter; embeddings require non-empty text"
}
```

If upstream cannot be changed, implementers should enforce validation in the proxy layer.

### Compatibility Matrix

| Model | Prompt Parameter | Input Parameter | Notes |
|-------|------------------|-----------------|-------|
| mxbai-embed-large | ✅ 1024-dim | ❌ FAIL (empty array) | Only prompt works |
| nomic-embed-text | ✅ 768-dim | ❌ FAIL (empty array) | Only prompt works |
| all-minilm | ✅ 384-dim | ❌ FAIL (empty array) | Only prompt works |

## Impact Assessment

### High Impact
- **OpenAI API Compatibility**: OpenAI embeddings API uses `input` parameter
- **Client Libraries**: Many embedding client libraries default to `input`
- **Migration Barrier**: Users migrating from other services may expect `input`

### Medium Impact
- **Documentation Clarity**: API documentation should specify parameter requirements
- **Error Handling**: Currently returns empty arrays instead of proper error messages

## Recommended Solutions

### Option 1: API Gateway/Proxy (Immediate)

Create a compatibility layer that properly handles JSON transformation:

```lua
# Improved OpenResty/Lua proxy configuration
location /api/embeddings {
    access_by_lua_block {
        local cjson = require "cjson"
        
        -- Read request body
        ngx.req.read_body()
        local body_data = ngx.req.get_body_data()
        
        if not body_data then
            ngx.status = 400
            ngx.say('{"error":"missing request body"}')
            ngx.exit(400)
        end
        
        -- Parse JSON safely
        local success, body_json = pcall(cjson.decode, body_data)
        if not success then
            ngx.status = 400
            ngx.say('{"error":"invalid JSON in request body"}')
            ngx.exit(400)
        end
        
        -- Transform input to prompt if needed
        if body_json.input and not body_json.prompt then
            if type(body_json.input) == "string" and body_json.input ~= "" then
                body_json.prompt = body_json.input
                body_json.input = nil
            elseif type(body_json.input) == "table" and #body_json.input > 0 then
                body_json.prompt = table.concat(body_json.input, " ")
                body_json.input = nil
            else
                ngx.status = 400
                ngx.say('{"error":"empty input parameter; embeddings require non-empty text"}')
                ngx.exit(400)
            end
            
            -- Re-encode and set body
            local new_body = cjson.encode(body_json)
            ngx.req.set_body_data(new_body)
            ngx.req.set_header("Content-Length", string.len(new_body))
        end
    }
    proxy_pass http://localhost:11434;
}
```

### Option 2: Client-Side Wrapper (Current)

Implement proper HTTP status checking and response validation:

```bash
# Improved client wrapper approach
get_embedding() {
    local model="$1"
    local text="$2"
    local host="$3"
    local port="$4"
    
    # Try OpenAI-style "input" parameter first
    local response=$(curl -s -w "%{http_code}" -X POST "http://${host}:${port}/api/embeddings" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"${model}\",\"input\":\"${text}\"}")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    # Check if request succeeded and has valid embedding
    if [[ "$http_code" == "200" ]] && echo "$body" | jq -e '.embedding | length > 0' >/dev/null 2>&1; then
        echo "$body"
        return 0
    fi
    
    # Fallback to "prompt" parameter
    response=$(curl -s -w "%{http_code}" -X POST "http://${host}:${port}/api/embeddings" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"${model}\",\"prompt\":\"${text}\"}")
    
    http_code="${response: -3}"
    body="${response%???}"
    
    if [[ "$http_code" == "200" ]] && echo "$body" | jq -e '.embedding | length > 0' >/dev/null 2>&1; then
        echo "$body"
        return 0
    else
        echo "ERROR: Both input and prompt parameters failed" >&2
        return 1
    fi
}
```

### Option 3: Ollama API Enhancement (Long-term)
Request Ollama upstream to support both parameters:

```json
{
  "model": "mxbai-embed-large",
  "input": "text here",     // Should be supported
  "prompt": "text here"     // Currently supported
}
```

## Current Workarounds

### 1. Enhanced Test Scripts
- ✅ `emb-smoke-enhanced.sh` - Parameter fallback detection
- ✅ `emb-compatibility-test.sh` - Compatibility validation

### 2. Client Guidelines
```bash
# Recommended client usage pattern
curl -X POST http://host:11434/api/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model":"mxbai-embed-large","prompt":"your text here"}'
  
# NOT: -d '{"model":"mxbai-embed-large","input":"your text here"}'
```

## Monitoring Recommendations

### 1. API Usage Monitoring
- Track failed embedding requests (empty arrays)
- Monitor client error rates
- Log parameter usage patterns

### 2. Compatibility Testing

- Regular compatibility tests with both parameters
- **HTTP Status Validation**: Check status codes (200 for success, 400 for bad requests)
- **Response Shape Validation**: Verify presence of embedding field and expected array length
- Semantic coherence testing

### Updated Testing Instructions

Instead of substring matching, use proper HTTP status and JSON validation:

```bash
# Check HTTP status and response structure
if [[ "$http_code" == "200" ]] && echo "$response" | jq -e '.embedding | length > 0' >/dev/null; then
    echo "✅ Valid embedding response"
else
    echo "❌ Invalid response or HTTP error"
fi
```

## Action Items

### Immediate (Phase 6)
- [x] Document compatibility issue
- [x] Create enhanced test scripts with fallback
- [x] Establish monitoring baseline
- [ ] Update API documentation
- [ ] Create client usage guidelines

### Short-term
- [ ] Implement API gateway/proxy solution if needed
- [ ] Update client libraries with parameter detection
- [ ] Monitor usage patterns and error rates

### Long-term
- [ ] Engage with Ollama upstream for dual parameter support
- [ ] Evaluate API versioning strategies
- [ ] Consider embedding service abstraction layer

## References

- **Ollama API Documentation**: Currently specifies `prompt` parameter
- **OpenAI Embeddings API**: Uses `input` parameter standard
- **HX-Infrastructure Standards**: Require compatibility documentation

---

**Last Updated**: August 14, 2025 23:20 UTC  
**Next Review**: Monitor client adoption and error patterns  
**Priority**: High (affects client compatibility)
