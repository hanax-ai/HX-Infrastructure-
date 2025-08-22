"""
Security services for the API Gateway.

Provides authentication and authorization functionality,
including write-scope validation for admin operations.
"""

import os
from typing import Optional
from fastapi import HTTPException, Request

# Environment configuration - fail fast for production
ENV = os.environ.get("ENV", "dev")
if ENV == "prod":
    HX_ADMIN_KEY = os.environ["HX_ADMIN_KEY"]  # Required in production
else:
    # Development fallback only for non-production environments
    HX_ADMIN_KEY = os.environ.get("HX_ADMIN_KEY", "sk-hx-admin-dev-2024")

def require_rag_write(request: Request) -> None:
    """
    Dependency to require write-scope authentication for RAG operations.
    
    Validates X-HX-Admin-Key header for administrative operations.
    Returns None on success (does not return the secret).
    
    Raises:
        HTTPException: 401 if authentication fails, 403 if key is invalid
    """
    # Check for X-HX-Admin-Key header
    admin_key = request.headers.get("X-HX-Admin-Key")
    if not admin_key:
        raise HTTPException(
            status_code=401,
            detail="Write operations require X-HX-Admin-Key header",
            headers={"WWW-Authenticate": "X-HX-Admin-Key"}
        )
    
    # Validate the admin key
    if admin_key != HX_ADMIN_KEY:
        raise HTTPException(
            status_code=403,
            detail="Invalid admin key for write operations"
        )
    
    # Return None instead of the secret to avoid accidental leakage
    return None

def extract_auth_header(request: Request) -> Optional[str]:
    """
    Extract Authorization header for embedding service calls.
    
    Returns the full Authorization header value or None.
    """
    return request.headers.get("Authorization")
