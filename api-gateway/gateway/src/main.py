from fastapi import FastAPI, Request
from starlette.responses import Response, JSONResponse
import json, httpx
import os

# Upstream LiteLLM (already running on 4000)
UPSTREAM = "http://127.0.0.1:4000"

app = FastAPI()

def check_auth(request: Request) -> bool:
    """Check authentication using the same logic as SecurityMiddleware"""
    # Allow health endpoints without auth
    if request.url.path in ("/healthz", "/livez", "/readyz"):
        return True
    
    # Check for valid bearer token
    auth = request.headers.get("authorization", "")
    if not auth.lower().startswith("bearer "):
        return False
    
    token = auth.split(" ", 1)[1] if len(auth.split(" ", 1)) > 1 else ""
    master_key = os.getenv("HX_MASTER_KEY") or os.getenv("MASTER_KEY") or "sk-hx-dev-default"
    
    return token == master_key

@app.middleware("http")
async def hx_pipeline(request: Request, call_next):
    path = request.url.path
    method = request.method.upper()

    # Local health (kept out of /v1/*)
    if path == "/healthz":
        return JSONResponse({"ok": True, "note": "HX wrapper – proxy mode"})

    # Only proxy /v1/* to LiteLLM; don't define any /v1 routes here.
    if path.startswith("/v1/"):
        # Check authentication first
        if not check_auth(request):
            return JSONResponse(
                {"error": "Unauthorized"},
                status_code=401,
                headers={"WWW-Authenticate": "Bearer"}
            )
        
        # Read/possibly transform body with size validation
        try:
            body = await request.body()
            # Prevent oversized payloads (max 1MB for API requests)
            max_body_size = int(os.getenv("HX_MAX_BODY_SIZE", "1048576"))  # 1MB default
            if len(body) > max_body_size:
                return JSONResponse(
                    {"error": "Payload too large", "max_size": max_body_size},
                    status_code=413
                )
        except Exception as e:
            return JSONResponse(
                {"error": "Invalid request body", "detail": str(e)},
                status_code=400
            )
            
        if path == "/v1/embeddings" and method == "POST":
            try:
                payload = json.loads(body or b"{}")
                # Validate payload structure before transformation
                if not isinstance(payload, dict):
                    return JSONResponse(
                        {"error": "Request body must be a JSON object"},
                        status_code=400
                    )
                # Fix: map "prompt" → "input" when payload has prompt but not input
                if "prompt" in payload and "input" not in payload:
                    payload["input"] = payload.pop("prompt")
                    body = json.dumps(payload).encode("utf-8")
            except json.JSONDecodeError as e:
                return JSONResponse(
                    {"error": "Invalid JSON in request body", "detail": str(e)},
                    status_code=400
                )
            except Exception as e:
                return JSONResponse(
                    {"error": "Request processing failed", "detail": str(e)},
                    status_code=500
                )

        # Build upstream URL (preserve query string)
        url = f"{UPSTREAM}{path}"
        if request.url.query:
            url += f"?{request.url.query}"

        # Forward headers with security filtering
        # Remove hop-by-hop headers (RFC 7230)
        hop_by_hop = {"host", "content-length", "accept-encoding", "connection", "transfer-encoding"}
        
        # Remove sensitive headers that should not be forwarded to upstream
        sensitive_headers = {
            "authorization",          # Authentication tokens
            "cookie",                # Session cookies
            "set-cookie",            # Response cookies
            "x-forwarded-for",       # Client IP chain (controlled below)
            "x-real-ip",            # Original client IP
            "x-forwarded-proto",     # Original protocol
            "x-forwarded-host",      # Original host
            "x-original-forwarded-for",  # Nested proxy headers
            "cf-connecting-ip",      # Cloudflare client IP
            "cf-ipcountry",         # Cloudflare country
            "x-cluster-client-ip",   # Cluster proxy headers
            "x-forwarded-server",    # Server information
            "proxy-authorization",   # Proxy auth
            "www-authenticate",      # Auth challenges
            "proxy-authenticate",    # Proxy auth challenges
        }
        
        # Build filtered headers (case-insensitive filtering)
        fwd_headers = {}
        for k, v in request.headers.items():
            key_lower = k.lower()
            if key_lower not in hop_by_hop and key_lower not in sensitive_headers:
                fwd_headers[k] = v
        
        # Controlled client IP propagation (if needed for upstream logging)
        # Only add X-Forwarded-For if explicitly configured and from trusted source
        trust_proxy_ip = os.getenv("HX_TRUST_PROXY_IP", "").lower() in ("true", "1", "yes")
        if trust_proxy_ip:
            # Get client IP from connection info (not from headers to prevent spoofing)
            client_ip = 'unknown'
            if request.client:
                # Try object attribute first (newer Starlette/FastAPI versions)
                client_ip = getattr(request.client, 'host', None)
                # Fall back to tuple/list format (older versions)
                if client_ip is None and isinstance(request.client, (tuple, list)) and len(request.client) > 0:
                    client_ip = request.client[0]
                # Ensure we have a valid string
                if client_ip is None:
                    client_ip = 'unknown'
            if client_ip != 'unknown':
                fwd_headers["X-HX-Client-IP"] = client_ip  # Use custom header to avoid confusion

        # Send to upstream
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                upstream = await client.request(method, url, headers=fwd_headers, content=body)
        except httpx.HTTPError as e:
            return JSONResponse(
                {"error": "upstream_unreachable", "detail": str(e)},
                status_code=502
            )

        # Return upstream response (strip hop-by-hop headers and add security headers)
        resp_headers = {
            k: v for k, v in upstream.headers.items()
            if k.lower() not in ("content-length", "transfer-encoding", "connection", "server", "date")
        }
        
        # Add security headers to response
        resp_headers.update({
            "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY",
            "X-XSS-Protection": "1; mode=block",
            "Referrer-Policy": "strict-origin-when-cross-origin",
            "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none';"
        })
        
        return Response(content=upstream.content, status_code=upstream.status_code, headers=resp_headers)

    # Anything else (non-API paths), let the app fall through (if you have extra local routes)
    return await call_next(request)
