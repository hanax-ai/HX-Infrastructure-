from __future__ import annotations
from prometheus_client import Counter, Histogram

rag_upserts = Counter("rag_upserts_total", "Total RAG upsert requests", ["result"])
rag_deletes = Counter("rag_deletes_total", "Total RAG delete requests", ["result", "mode"])
rag_search  = Counter("rag_search_total",  "Total RAG search requests",  ["result", "path"])

embed_latency = Histogram("rag_embedding_seconds", "Embedding call latency (s)")
qdrant_latency = Histogram("rag_qdrant_seconds", "Qdrant call latency (s)", ["op"])
