import asyncio
import os
from typing import Optional

import redis.asyncio as aioredis


class RedisService:
    """SRP: Redis health; non-blocking redis.asyncio with timeout."""

    def __init__(self, url: Optional[str] = None, timeout_s: float = 2.0):
        self.url = url or os.getenv("REDIS_URL", "")
        self.timeout = timeout_s
        self._client: aioredis.Redis | None = None

    async def connect(self) -> None:
        if not self.url or self._client:
            return
        self._client = aioredis.from_url(
            self.url, decode_responses=True, socket_connect_timeout=self.timeout
        )

    async def healthy(self) -> bool:
        try:
            await asyncio.wait_for(self._healthy_impl(), timeout=self.timeout)
            return True
        except Exception:
            return False

    async def _healthy_impl(self) -> None:
        await self.connect()
        if not self._client:
            raise RuntimeError("redis client not available")
        await self._client.ping()
