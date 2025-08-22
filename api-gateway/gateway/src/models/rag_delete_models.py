"""
RAG Delete Request/Response Models

Pydantic models for RAG document deletion operations with comprehensive validation
and clear error handling. Supports ID-based, namespace-based, and filter-based deletions.
"""

from __future__ import annotations
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field, ConfigDict


class DeleteByIdsRequest(BaseModel):
    """Request model for deleting documents by specific point IDs."""
    model_config = ConfigDict(extra="forbid")
    
    ids: List[str] = Field(
        ..., 
        min_length=1, 
        description="Point IDs to delete from the vector database",
        examples=[["doc_123_chunk_1", "doc_123_chunk_2"]]
    )


class DeleteByNamespaceRequest(BaseModel):
    """Request model for bulk deletion of all documents in a namespace."""
    model_config = ConfigDict(extra="forbid")
    
    namespace: str = Field(
        ..., 
        min_length=1, 
        description="Namespace to delete (all documents within will be removed)",
        examples=["docs:test", "customer:acme", "project:alpha"]
    )


class DeleteByFilterRequest(BaseModel):
    """Request model for filter-based document deletion using Qdrant filter syntax."""
    model_config = ConfigDict(extra="forbid")
    
    must: Optional[List[Dict[str, Any]]] = Field(
        None,
        description="Conditions that must match (AND logic)",
        examples=[[{"key": "source", "match": {"value": "pdf"}}]]
    )
    should: Optional[List[Dict[str, Any]]] = Field(
        None,
        description="Conditions that should match (OR logic)",
        examples=[[{"key": "category", "match": {"value": "manual"}}]]
    )
    must_not: Optional[List[Dict[str, Any]]] = Field(
        None,
        description="Conditions that must not match (NOT logic)",
        examples=[[{"key": "deprecated", "match": {"value": "true"}}]]
    )


class DeleteResponse(BaseModel):
    """Standardized response for all delete operations."""
    
    status: str = Field(
        description="Operation status",
        examples=["ok", "error"]
    )
    deleted: int = Field(
        description="Number of documents deleted (-1 if unknown)",
        examples=[5, -1]
    )
    detail: Optional[str] = Field(
        None,
        description="Additional operation details or instructions",
        examples=["count unknown; use /points/count to verify"]
    )
