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
        req = context["request"]
        path = req.url.path
        method = req.method.upper()
        headers = dict(req.headers)
        # Force upstream auth with same bearer (LiteLLM master_key)
        # or strip it if LiteLLM is open in dev
        body = context.get("normalized_body")
        if method == "POST":
            r = await self._client.post(path, headers=headers, content=body or await req.body())
        else:
            r = await self._client.request(method, path, headers=headers)
        context["response"] = Response(status_code=r.status_code, content=r.content, headers=r.headers)
        return context
