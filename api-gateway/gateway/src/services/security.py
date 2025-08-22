"""
Security services for the API Gateway.

Provides authentication and authorization functionality,
including write-scope validation for admin operations.
"""

from __future__ import annotations

import os
from typing import Optional

from fastapi import Header, HTTPException, Request

# Environment configuration - fail fast for production
ENV = os.environ.get("ENV", "dev")
if ENV == "prod":
    HX_ADMIN_KEY = os.environ["HX_ADMIN_KEY"]  # Required in production
else:
    # Development fallback only for non-production environments
    HX_ADMIN_KEY = os.environ.get("HX_ADMIN_KEY", "sk-hx-admin-dev-2024")


def _allowed_admin_keys() -> set[str]:
    """Allow multiple keys via ADMIN_KEYS; fallback ADMIN_KEY; also RAG_WRITE_KEY for legacy."""
    # Allow multiple keys via ADMIN_KEYS; fallback ADMIN_KEY; also RAG_WRITE_KEY for legacy
    keys = os.getenv("ADMIN_KEYS") or os.getenv("ADMIN_KEY") or os.getenv("RAG_WRITE_KEY", "")
    return {k.strip() for k in keys.split(",") if k.strip()}


async def require_rag_write(
    x_hx_admin_key: str | None = Header(default=None, alias="X-HX-Admin-Key")
) -> str:
    """
    Dependency to require write-scope authentication for RAG operations.

    Validates X-HX-Admin-Key header for administrative operations.
    Returns the validated key on success.

    Raises:
        HTTPException: 401 if authentication missing or invalid
    """
    allowed = _allowed_admin_keys()
    if not x_hx_admin_key or (allowed and x_hx_admin_key not in allowed):
        # Tests expect 401 for missing OR wrong key
        raise HTTPException(status_code=401, detail="Authentication required")
    return x_hx_admin_key


def extract_auth_header(request: Request) -> str | None:
    """
    Extract Authorization header for embedding service calls.

    Returns the full Authorization header value or None.
    """
    return request.headers.get("Authorization")


def get_embedding_auth_from_request(request: Request) -> str | None:
    """
    Helper to get embedding auth from request or environment.

    Returns authorization header or environment fallback.
    """
    return request.headers.get("authorization") or os.getenv("EMBEDDING_AUTH_HEADER")


async def get_embedding_auth_from_dependency(request: Request) -> str:
    """
    FastAPI dependency to extract embedding auth from request.
    
    Returns authorization header or environment fallback.
    Raises 401 if no authentication is available.
    """
    auth = get_embedding_auth_from_request(request)
    if not auth:
        raise HTTPException(status_code=401, detail="Authorization required for embedding operations")
    return auth


async def get_embedding_auth(authorization: str | None = Header(default=None, alias="Authorization")) -> str:
    """
    FastAPI dependency for embedding authentication via header.
    
    Can be used with Depends() in route definitions.
    Falls back to environment if no header provided.
    """
    if authorization:
        return authorization
    
    # Fallback to environment
    fallback = os.getenv("EMBEDDING_AUTH_HEADER")
    if fallback:
        return fallback
        
    raise HTTPException(status_code=401, detail="Authorization required for embedding operations")
