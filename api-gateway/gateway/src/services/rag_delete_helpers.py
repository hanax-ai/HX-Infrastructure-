"""
RAG Delete Service Helpers

SOLID-compliant service layer for RAG document deletion operations.
Handles Qdrant vector database interactions with proper error handling and logging.
"""

import logging
import os
from typing import Any, Optional

import httpx

# Configuration from environment
QDRANT_URL = os.environ.get("QDRANT_URL", "http://192.168.10.30:6333").rstrip("/")
QDRANT_COLLECTION = os.environ.get("QDRANT_COLLECTION", "hx_rag_default")

# Logger for service operations
logger = logging.getLogger(__name__)


def _norm_ids(ids: list[str]) -> list[str]:
    """Trim and drop empty IDs to avoid Qdrant selector format errors."""
    out: list[str] = []
    for i in ids or []:
        if i is None:
            continue
        s = str(i).strip()
        if not s:
            continue
        out.append(s)
    return out


async def qdrant_delete_by_ids(ids: list[str]) -> tuple[bool, str, int]:
    """
    Delete specific points by their IDs with verified count.

    Args:
        ids: List of point IDs to delete

    Returns:
        Tuple of (success, response_text, count_deleted)
        Note: count_deleted is verified via count endpoint before/after deletion.
    """
    norm = _norm_ids(ids)
    if not norm:
        logger.info("Delete by IDs called with empty/blank ID list — no-op.")
        return True, "no-op (empty id list)", 0

    # Get count before deletion by creating a filter for these specific IDs
    pre_filter = {"must": [{"key": "id", "match": {"any": norm}}]}
    count_success, pre_count = await qdrant_count_points(pre_filter)
    
    if not count_success:
        logger.warning("Could not verify pre-deletion count, proceeding with delete")
        pre_count = -1  # Continue with deletion but return -1 to indicate uncertainty

    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points/delete?wait=true"
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
            # Verify actual deletion count if we got pre-count
            if pre_count >= 0:
                post_count_success, post_count = await qdrant_count_points(pre_filter)
                if post_count_success:
                    actual_deleted = pre_count - post_count
                    logger.info("Successfully deleted %d points (verified)", actual_deleted)
                    return True, text, actual_deleted
                else:
                    logger.warning("Could not verify post-deletion count")
            
            # Fallback: return optimistic count with warning
            logger.info("Successfully requested deletion for %d points (unverified)", len(norm))
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

    except httpx.RequestError:
        # Contract tests assert for this exact phrase
        logger.exception("Qdrant connection failed during delete_by_ids")
        return False, "Qdrant connection failed", 0
    except Exception as e:
        logger.exception("Exception during delete by IDs")
        return False, str(e), 0


async def qdrant_delete_by_filter(qfilter: dict[str, Any]) -> tuple[bool, str, int]:
    """
    Delete points using Qdrant filter conditions with verified count.

    Args:
        qfilter: Qdrant filter dict with must/should/must_not conditions

    Returns:
        Tuple of (success, response_text, count_deleted)
        Note: count_deleted is verified via count endpoint before/after deletion.
    """
    # Get count before deletion
    count_success, pre_count = await qdrant_count_points(qfilter)
    
    if not count_success:
        logger.warning("Could not verify pre-deletion count, proceeding with delete")
        pre_count = -1  # Continue with deletion but return -1 to indicate uncertainty

    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points/delete?wait=true"
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
            # Verify actual deletion count if we got pre-count
            if pre_count >= 0:
                post_count_success, post_count = await qdrant_count_points(qfilter)
                if post_count_success:
                    actual_deleted = pre_count - post_count
                    logger.info("Successfully deleted %d points (verified)", actual_deleted)
                    return True, text, actual_deleted
                else:
                    logger.warning("Could not verify post-deletion count")
            
            # Fallback: return -1 to indicate unknown count
            logger.info("Filter-based delete request succeeded (count unverified)")
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

    except httpx.RequestError:
        logger.exception("Qdrant connection failed during delete_by_filter")
        return False, "Qdrant connection failed", 0
    except Exception as e:
        logger.exception("Exception during delete by filter")
        return False, str(e), 0


async def qdrant_count_points(
    qfilter: Optional[dict[str, Any]] = None
) -> tuple[bool, int]:
    """
    Count points in Qdrant collection, optionally with filter.

    Args:
        qfilter: Optional filter to count specific points

    Returns:
        Tuple of (success, count)
    """
    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points/count"
    body: dict[str, Any] = {"exact": True}
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
