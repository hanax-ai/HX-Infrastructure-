# Services module for database, cache, and vector database integrations
"""
Database, Cache, and Vector Database Services

This module provides async service wrappers for:
- PostgreSQL (asyncpg)
- Redis (redis.asyncio) 
- Qdrant (httpx)

Used by DB-Guard middleware for health checks and basic operations.
"""

__version__ = "1.0.0"
