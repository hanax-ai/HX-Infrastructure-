# /opt/HX-Infrastructure-/api-gateway/gateway/src/middlewares/base.py
from typing import Any


class MiddlewareBase:
    async def process(self, context: dict[str, Any]) -> dict[str, Any]:
        return context
