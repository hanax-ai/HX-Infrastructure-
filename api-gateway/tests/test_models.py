# tests/test_models.py
import pytest
from gateway.src.models.rag_upsert_models import UpsertDoc, UpsertRequest
from pydantic import ValidationError


def test_upsertdoc_allows_text_or_vector():
    d1 = UpsertDoc(text="hello", namespace="ns")
    d2 = UpsertDoc(vector=[0.0] * 8, namespace="ns")  # small OK at model layer
    assert d1.text == "hello"
    assert isinstance(d2.vector, list)


def test_upsertrequest_requires_documents():
    with pytest.raises(ValidationError):
        UpsertRequest(documents=[])


def test_upsertrequest_batch_size_bounds():
    with pytest.raises(ValidationError):
        UpsertRequest(documents=[UpsertDoc(text="t")], batch_size=0)
    r = UpsertRequest(documents=[UpsertDoc(text="t")], batch_size=128)
    assert r.batch_size == 128
