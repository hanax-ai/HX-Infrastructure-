"""
RAG Upsert Models Module

This module contains Pydantic models for RAG document upsert operations,
following SOLID principles with proper validation and type safety.
"""

from typing import Any, Optional

from pydantic import BaseModel, Field, model_validator


class UpsertDoc(BaseModel):
    id: Optional[str] = None
    text: Optional[str] = None
    # Accept any float list here; service enforces EMBEDDING_DIM.
    vector: Optional[list[float]] = None
    metadata: Optional[dict[str, Any]] = None
    # Optional at model layer; services/routes may require or inject it.
    namespace: Optional[str] = Field(default=None, min_length=1, max_length=200)

    @model_validator(mode="after")
    def _require_text_or_vector(self) -> "UpsertDoc":
        if not (self.text or self.vector):
            raise ValueError("Document must provide either 'text' or 'vector'")
        return self


class UpsertRequest(BaseModel):
    documents: list[UpsertDoc] = Field(..., min_length=1, max_length=100)
    batch_size: int = Field(default=32, ge=1, le=128)


class UpsertResponse(BaseModel):
    status: str
    upserted: int
    failed: int
    # Always include 'details' key (even if empty) – tests assert its presence.
    details: list[dict[str, Any]] = Field(default_factory=list)
    errors: list[str] = Field(default_factory=list)
    request_id: Optional[str] = None
    processing_time_ms: Optional[int] = None
