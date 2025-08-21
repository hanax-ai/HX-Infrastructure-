# /opt/HX-Infrastructure-/api-gateway/gateway/src/middlewares/execution.py
import os, json, httpx
from typing import Any, Dict
from fastapi import Response
from .base import MiddlewareBase

class ExecutionMiddleware(MiddlewareBase):
    def __init__(self) -> None:
        # SOLID Principle: Dependency Inversion - configurable upstream via environment
        # HTTPx timeout configuration following SOLID principles:
        # - Single Responsibility: Each timeout handles one aspect (connect/read/write/pool)
        # - Open/Closed: Timeout configuration extensible without changing core logic
        self._client = httpx.AsyncClient(
            base_url=os.getenv("HX_LITELLM_UPSTREAM", "http://127.0.0.1:4000"),
            timeout=httpx.Timeout(
                connect=2.0,    # Connection establishment timeout
                read=30.0,      # Response read timeout for ML inference
                write=10.0,     # Request write timeout
                pool=5.0        # Connection pool timeout
            ),
        )

    async def process(self, context: Dict[str, Any]) -> Dict[str, Any]:
        request = context["request"]
        path = request.url.path
        method = request.method.upper()

        # Use transformed body if available, otherwise original request body
        body = context.get("transformed_body")
        if body is None:
            body = await request.body()

        # Build upstream URL, preserving the query string
        url = f"{self._client.base_url}{path}"
        if request.url.query:
            url += f"?{request.url.query}"

        # Header filtering logic migrated from main.py
        hop_by_hop = {"host", "content-length", "accept-encoding", "connection", "transfer-encoding"}
        sensitive_headers = {
            "authorization", "cookie", "set-cookie", "x-forwarded-for", "x-real-ip",
            "x-forwarded-proto", "x-forwarded-host", "x-original-forwarded-for",
            "cf-connecting-ip", "cf-ipcountry", "x-cluster-client-ip",
            "x-forwarded-server", "proxy-authorization", "www-authenticate", "proxy-authenticate"
        }
        
        fwd_headers = {
            k: v for k, v in request.headers.items()
            if k.lower() not in hop_by_hop and k.lower() not in sensitive_headers
        }

        # Upstream authentication
        upstream_key = os.getenv("HX_UPSTREAM_KEY")
        if upstream_key:
            fwd_headers["Authorization"] = f"Bearer {upstream_key}"
        
        # Add client IP if trusted
        if os.getenv("HX_TRUST_PROXY_IP", "").lower() in ("true", "1", "yes") and request.client:
            fwd_headers["X-HX-Client-IP"] = request.client.host

        try:
            upstream_response = await self._client.request(
                method, url, headers=fwd_headers, content=body
            )
        except httpx.TimeoutException as e:
            context["response"] = Response(
                status_code=504,
                content=json.dumps({"error": "upstream_timeout", "detail": str(e)}).encode(),
                media_type="application/json"
            )
            return context
        except httpx.HTTPError as e:
            context["response"] = Response(
                status_code=502,
                content=json.dumps({"error": "upstream_unreachable", "detail": str(e)}).encode(),
                media_type="application/json"
            )
            return context

        # Filter response headers and add security headers
        resp_headers = {
            k: v for k, v in upstream_response.headers.items()
            if k.lower() not in ("content-length", "transfer-encoding", "connection", "server", "date")
        }
        
        # Add base security headers, but handle CSP separately
        resp_headers.update({
            "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY",
            "X-XSS-Protection": "1; mode=block",
            "Referrer-Policy": "strict-origin-when-cross-origin",
        })

        # Conditionally set Content-Security-Policy, respecting upstream's if present
        if "content-security-policy" not in (k.lower() for k in resp_headers.keys()):
            content_type = resp_headers.get("content-type", "").lower()
            if content_type.startswith("text/html"):
                # For HTML, allow content from the same origin as a safe default.
                resp_headers["Content-Security-Policy"] = "default-src 'self'; frame-ancestors 'none';"
            else:
                # For non-HTML (e.g., JSON APIs), lock it down completely.
                resp_headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none';"


        context["response"] = Response(
            content=upstream_response.content,
            status_code=upstream_response.status_code,
            headers=resp_headers
        )
        return context
