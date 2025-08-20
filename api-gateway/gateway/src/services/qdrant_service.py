from typing import Optional
import os, asyncio
import httpx

class QdrantService:
    """SRP: Qdrant health via HTTP GET /collections; non-blocking httpx."""
    def __init__(self, url: Optional[str] = None, timeout_s: float = 3.0):
        self.url = (url or os.getenv("QDRANT_URL", "")).rstrip("/")
        self.timeout = timeout_s

    async def healthy(self) -> bool:
        if not self.url: 
            return False
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                r = await client.get(f"{self.url}/collections")
                return r.status_code == 200
        except Exception:
            return False
