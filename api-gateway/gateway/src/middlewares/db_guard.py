from typing import Dict, Any, Sequence
from fastapi import HTTPException, status

class DBGuardMiddleware:
    """
    SRP: Guard DB-required routes. On outage return 503 with explicit cause.
    """
    def __init__(self, pg, redis, guarded_prefixes: Sequence[str]):
        self.pg = pg
        self.redis = redis
        self.guarded = tuple(guarded_prefixes)

    async def process(self, context: Dict[str, Any]) -> Dict[str, Any]:
        path = context["request"].url.path
        if path.startswith(self.guarded):
            pg_ok, rd_ok = await self.pg.healthy(), await self.redis.healthy()
            if not (pg_ok and rd_ok):
                missing = []
                if not pg_ok: missing.append("PostgreSQL")
                if not rd_ok: missing.append("Redis")
                raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                                    detail=f"Gateway dependency unavailable: {', '.join(missing)}.")
        return context
