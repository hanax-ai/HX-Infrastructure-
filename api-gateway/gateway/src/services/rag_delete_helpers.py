"""
RAG Delete Service Helpers

SOLID-compliant service layer for RAG document deletion operations.
Handles Qdrant vector database interactions with proper error handling and logging.
"""

import os
import logging
from typing import Any, Dict, List, Optional, Tuple

import httpx

# Configuration from environment
QDRANT_URL = os.environ.get("QDRANT_URL", "http://192.168.10.30:6333").rstrip("/")
QDRANT_COLLECTION = os.environ.get("QDRANT_COLLECTION", "hx_rag_default")

# Logger for service operations
logger = logging.getLogger(__name__)


def _norm_ids(ids: List[str]) -> List[str]:
    """Trim and drop empty IDs to avoid Qdrant selector format errors."""
    out: List[str] = []
    for i in ids or []:
        if i is None:
            continue
        s = str(i).strip()
        if not s:
            continue
        out.append(s)
    return out


async def qdrant_delete_by_ids(ids: List[str]) -> Tuple[bool, str, int]:
    """
    Delete specific points by their IDs.

    Args:
        ids: List of point IDs to delete

    Returns:
        Tuple of (success, response_text, count_deleted)
        Note: count_deleted is len(ids) on success; use /points/count to verify.
    """
    norm = _norm_ids(ids)
    if not norm:
        logger.info("Delete by IDs called with empty/blank ID list — no-op.")
        return True, "no-op (empty id list)", 0

    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points/delete"
    # Qdrant expects PointsSelector: {"points": [...]} — include wait for sync ops
    body = {"points": norm, "wait": True}

    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            logger.info(
                "Deleting %d points by IDs from Qdrant collection %s",
                len(norm),
                QDRANT_COLLECTION,
            )
            response = await client.post(url, json=body)

        ok = response.status_code == 200
        text = response.text

        if ok:
            logger.info("Successfully requested deletion for %d points", len(norm))
            return True, text, len(norm)

        # Log more detail (best-effort JSON parse)
        try:
            err_json = response.json()
            logger.error("Qdrant delete_by_ids error: %s", err_json)
        except Exception:
            logger.error(
                "Qdrant delete_by_ids error: %s - %s",
                response.status_code,
                text[:500],
            )
        return False, text, 0

    except Exception as e:
        logger.error("Exception during delete by IDs: %s", str(e))
        return False, str(e), 0


async def qdrant_delete_by_filter(qfilter: Dict[str, Any]) -> Tuple[bool, str, int]:
    """
    Delete points using Qdrant filter conditions.

    Args:
        qfilter: Qdrant filter dict with must/should/must_not conditions

    Returns:
        Tuple of (success, response_text, count_deleted)
        Note: count_deleted is -1 for filter-based deletes. Use /points/count to verify.
    """
    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points/delete"
    body = {"filter": qfilter, "wait": True}

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            logger.info(
                "Deleting points by filter from Qdrant collection %s: %s",
                QDRANT_COLLECTION,
                qfilter,
            )
            response = await client.post(url, json=body)

        ok = response.status_code == 200
        text = response.text

        if ok:
            logger.info("Filter-based delete request succeeded")
            return True, text, -1

        try:
            err_json = response.json()
            logger.error("Qdrant delete_by_filter error: %s", err_json)
        except Exception:
            logger.error(
                "Qdrant delete_by_filter error: %s - %s",
                response.status_code,
                text[:500],
            )
        return False, text, 0

    except Exception as e:
        logger.error("Exception during delete by filter: %s", str(e))
        return False, str(e), 0


async def qdrant_count_points(qfilter: Optional[Dict[str, Any]] = None) -> Tuple[bool, int]:
    """
    Count points in Qdrant collection, optionally with filter.

    Args:
        qfilter: Optional filter to count specific points

    Returns:
        Tuple of (success, count)
    """
    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points/count"
    body: Dict[str, Any] = {"exact": True}
    if qfilter:
        body["filter"] = qfilter

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(url, json=body)

        if response.status_code == 200:
            result = response.json()
            count = result.get("result", {}).get("count", 0)
            logger.info("Point count query successful: %d points", count)
            return True, count

        try:
            err_json = response.json()
            logger.error("Qdrant count error: %s", err_json)
        except Exception:
            logger.error(
                "Failed to count points: %s - %s",
                response.status_code,
                response.text[:500],
            )
        return False, 0

    except Exception as e:
        logger.error("Exception during point count: %s", str(e))
        return False, 0
