# /opt/HX-Infrastructure-/api-gateway/gateway/src/middlewares/base.py
from typing import Any, Dict

class MiddlewareBase:
    async def process(self, context: Dict[str, Any]) -> Dict[str, Any]:
        return context
