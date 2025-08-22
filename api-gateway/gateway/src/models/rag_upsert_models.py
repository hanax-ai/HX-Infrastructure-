"""
RAG Upsert Models Module

This module contains Pydantic models for RAG document upsert operations,
following SOLID principles with proper validation and type safety.
"""

from typing import Any, Dict, List, Optional, Union
from pydantic import BaseModel, Field, field_validator, model_validator
import uuid


class UpsertDoc(BaseModel):
    """
    Individual document for upsert operation.
    
    Supports either text (for embedding generation) or pre-computed vector.
    Includes metadata and namespace for proper organization.
    """
    
    id: Optional[str] = Field(
        default=None,
        description="Document ID. If not provided, will be generated from namespace + text hash"
    )
    
    text: Optional[str] = Field(
        default=None,
        min_length=1,
        max_length=8192,  # Conservative per-doc char limit
        description="Document text content for embedding generation"
    )
    
    vector: Optional[List[float]] = Field(
        default=None,
        description="Pre-computed embedding vector (1024 dimensions)"
    )
    
    namespace: str = Field(
        ...,
        min_length=1,
        max_length=128,
        pattern=r'^[a-zA-Z0-9:_-]+$',  # Schema hygiene: alphanumeric, colon, underscore, dash
        description="Document namespace for organization and filtering"
    )
    
    metadata: Dict[str, Any] = Field(
        default_factory=dict,
        description="Additional metadata (source, title, path, etc.)"
    )
    
    @field_validator('metadata')
    @classmethod
    def validate_metadata(cls, v):
        """Ensure metadata keys are lowercase for schema hygiene."""
        if not isinstance(v, dict):
            raise ValueError("Metadata must be a dictionary")
        
        # Normalize keys to lowercase for consistency
        normalized = {}
        for key, value in v.items():
            if not isinstance(key, str):
                raise ValueError("Metadata keys must be strings")
            normalized[key.lower()] = value
        
        return normalized
    
    @model_validator(mode='after')
    def validate_text_or_vector(self):
        """Ensure either text or vector is provided (and non-empty)."""
        text = self.text
        vector = self.vector
        
        # Check if both are None/empty
        if (text is None or text.strip() == "") and (vector is None or len(vector) == 0):
            raise ValueError("Either 'text' or 'vector' must be provided and non-empty")
        
        # Check if both are provided
        if (text is not None and text.strip() != "") and (vector is not None and len(vector) > 0):
            raise ValueError("Provide either 'text' or 'vector', not both")
        
        # Validate text is non-blank if provided
        if text is not None and text.strip() == "":
            raise ValueError("'text' must be a non-blank string")
        
        # Validate vector is non-empty list of floats if provided
        if vector is not None:
            if not isinstance(vector, list) or len(vector) == 0:
                raise ValueError("'vector' must be a non-empty list of floats")
            if not all(isinstance(x, (int, float)) for x in vector):
                raise ValueError("'vector' elements must be numeric")
        
        return self
    
    @field_validator('vector')
    @classmethod
    def validate_vector_dimensions(cls, v):
        """Validate vector dimensions if provided."""
        if v is not None:
            if not isinstance(v, list):
                raise ValueError("Vector must be a list of floats")
            
            if len(v) != 1024:
                raise ValueError("Vector must be exactly 1024 dimensions")
            
            if not all(isinstance(x, (int, float)) for x in v):
                raise ValueError("Vector elements must be numeric")
        
        return v


class UpsertRequest(BaseModel):
    """
    Request model for batch document upsert operations.
    
    Includes batch processing configuration and validation constraints.
    """
    
    documents: List[UpsertDoc] = Field(
        ...,
        min_items=1,
        max_items=100,  # Reasonable batch size limit
        description="List of documents to upsert"
    )
    
    batch_size: int = Field(
        default=32,
        ge=1,
        le=128,
        description="Processing batch size for embeddings and upserts"
    )
    
    @field_validator('documents')
    @classmethod
    def validate_documents_not_empty(cls, v):
        """Ensure documents list is not empty."""
        if not v:
            raise ValueError("Documents list cannot be empty")
        return v


class UpsertResponse(BaseModel):
    """
    Response model for upsert operations.
    
    Provides detailed status information and operation results.
    """
    
    status: str = Field(
        ...,
        description="Operation status: 'ok', 'partial', or 'error'"
    )
    
    upserted: int = Field(
        default=0,
        ge=0,
        description="Number of documents successfully upserted"
    )
    
    failed: int = Field(
        default=0,
        ge=0,
        description="Number of documents that failed to upsert"
    )
    
    errors: List[str] = Field(
        default_factory=list,
        description="List of error messages for failed operations"
    )
    
    request_id: str = Field(
        default_factory=lambda: str(uuid.uuid4()),
        description="Unique request identifier for tracking"
    )
    
    processing_time_ms: Optional[float] = Field(
        default=None,
        ge=0,
        description="Total processing time in milliseconds"
    )
