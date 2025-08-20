"""
PostgreSQL Service - Async wrapper for database operations

SRP: Single Responsibility - Postgres health & minimal query; non-blocking using asyncpg.
OCP: Open/Closed - Can be extended without modification
LSP: Liskov Substitution - Can be substituted by any database service interface
ISP: Interface Segregation - Minimal, focused interface
DIP: Dependency Inversion - Depends on abstractions (environment config)

Provides health checks and minimal query functionality using asyncpg.
Used by DB-Guard middleware for database connectivity verification.
"""

from typing import Optional, Mapping, Any
import asyncpg
import os
import asyncio
import logging

logger = logging.getLogger(__name__)


class PostgresService:
    """SRP: Postgres health & minimal query; non-blocking using asyncpg."""
    
    def __init__(self, url: Optional[str] = None, timeout_s: float = 3.0):
        """
        Initialize PostgreSQL service with connection URL and timeout.
        
        Args:
            url: Database connection URL (falls back to PG_URL env var)
            timeout_s: Connection and query timeout in seconds
        """
        self.url = url or os.getenv("PG_URL", "")
        self.timeout = timeout_s
        self._pool: asyncpg.Pool | None = None

    async def connect(self) -> None:
        """
        Establish connection pool if not already connected.
        Handles URL format conversion from psycopg to asyncpg format.
        Non-blocking operation with timeout protection.
        """
        if not self.url or self._pool:
            return
            
        try:
            # Convert postgresql+psycopg URL format to asyncpg format
            asyncpg_url = self.url.replace("postgresql+psycopg", "postgresql")
            
            self._pool = await asyncpg.create_pool(
                dsn=asyncpg_url,
                min_size=1, 
                max_size=5, 
                timeout=self.timeout
            )
            logger.info("PostgreSQL connection pool established")
        except Exception as e:
            logger.error(f"Failed to create PostgreSQL pool: {e}")
            self._pool = None

    async def healthy(self) -> bool:
        """
        Perform health check with timeout protection.
        Returns True if database is accessible, False otherwise.
        Non-blocking operation that won't hang the event loop.
        """
        try:
            await asyncio.wait_for(self._healthy_impl(), timeout=self.timeout)
            return True
        except Exception as e:
            logger.warning(f"PostgreSQL health check failed: {e}")
            return False

    async def _healthy_impl(self) -> None:
        """
        Internal health check implementation.
        Establishes connection and executes simple query.
        Raises exception on failure for timeout handling.
        """
        await self.connect()
        if not self._pool:
            raise RuntimeError("pg pool not available")
        
        async with self._pool.acquire() as con:
            result = await con.fetchval("SELECT 1;")
            if result != 1:
                raise RuntimeError(f"Unexpected health check result: {result}")

    async def close(self) -> None:
        """
        Gracefully close connection pool.
        Safe to call multiple times.
        """
        if self._pool:
            await self._pool.close()
            self._pool = None
            logger.info("PostgreSQL pool closed")
