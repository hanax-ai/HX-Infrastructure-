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
        
        # Read/possibly transform body
        body = await request.body()
        if path == "/v1/embeddings" and method == "POST":
            try:
                payload = json.loads(body or b"{}")
                # Fix: map "prompt" → "input" when payload has prompt but not input
                if isinstance(payload, dict) and "prompt" in payload and "input" not in payload:
                    payload["input"] = payload.pop("prompt")
                    body = json.dumps(payload).encode("utf-8")
            except Exception:
                # If body isn't JSON, just pass it through unchanged
                pass

        # Build upstream URL (preserve query string)
        url = f"{UPSTREAM}{path}"
        if request.url.query:
            url += f"?{request.url.query}"

        # Forward headers minus hop-by-hop / auto headers (case-insensitive)
        hop_by_hop = {"host", "content-length", "accept-encoding", "connection", "transfer-encoding"}
        fwd_headers = {k: v for k, v in request.headers.items() if k.lower() not in hop_by_hop}

        # Send to upstream
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                upstream = await client.request(method, url, headers=fwd_headers, content=body)
        except httpx.HTTPError as e:
            return JSONResponse(
                {"error": "upstream_unreachable", "detail": str(e)},
                status_code=502
            )

        # Return upstream response (strip hop-by-hop headers)
        resp_headers = {
            k: v for k, v in upstream.headers.items()
            if k.lower() not in ("content-length", "transfer-encoding", "connection", "server", "date")
        }
        return Response(content=upstream.content, status_code=upstream.status_code, headers=resp_headers)

    # Anything else (non-API paths), let the app fall through (if you have extra local routes)
    return await call_next(request)
