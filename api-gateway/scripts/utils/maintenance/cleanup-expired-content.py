#!/usr/bin/env python3
"""
TTL Cleanup Script - Removes expired documents from Qdrant
Designed for nightly cron execution to maintain clean vector store.

Usage:
    python3 cleanup-expired-content.py [--dry-run] [--batch-size=1000]
"""

import argparse
import asyncio
import logging
import os
import sys
from datetime import datetime, timezone
from typing import Any, Optional

import httpx
from pydantic import BaseModel

# Configure logging
log_file_path = "/var/log/hx-gateway-ml/ttl-cleanup.log"
log_handlers = [logging.StreamHandler()]  # Always include console logging

try:
    os.makedirs(os.path.dirname(log_file_path), exist_ok=True)
    log_handlers.append(logging.FileHandler(log_file_path))
except OSError as e:
    print(
        f"Error: Could not create log directory {os.path.dirname(log_file_path)}: {e}"
    )
    print(
        "Please ensure the process has appropriate permissions or create the directory manually."
    )
    sys.exit(1)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=log_handlers,
)
logger = logging.getLogger(__name__)


def build_auth_headers(config: "CleanupConfig") -> dict[str, str]:
    """
    Build authentication headers for Qdrant API requests.
    
    Args:
        config: Cleanup configuration containing admin_key
        
    Returns:
        Dictionary of headers to include in requests
    """
    headers = {"Content-Type": "application/json"}
    
    if config.admin_key:
        # Use X-Api-Key header for Qdrant authentication
        headers["X-Api-Key"] = config.admin_key
        
    return headers


class CleanupConfig(BaseModel):
    """Configuration for TTL cleanup operation."""

    qdrant_url: str = "http://localhost:6333"
    collection_name: str = "hx_embeddings"
    batch_size: int = 1000
    dry_run: bool = False
    admin_key: Optional[str] = None


class CleanupStats(BaseModel):
    """Statistics from cleanup operation."""

    total_scanned: int = 0
    total_expired: int = 0
    total_deleted: int = 0
    namespaces_affected: list[str] = []
    errors: list[str] = []
    execution_time_seconds: float = 0.0


async def delete_expired_by_filter(
    client: httpx.AsyncClient, config: CleanupConfig
) -> dict[str, Any]:
    """
    Delete expired documents using atomic server-side filter operation.

    Args:
        client: HTTP client for Qdrant API
        config: Cleanup configuration

    Returns:
        Dictionary with deletion results including count and operation status
    """
    current_time = datetime.now(timezone.utc).isoformat()

    if config.dry_run:
        # For dry-run, first query to get count and details
        query_payload = {
            "filter": {"must": [{"key": "expires_at", "range": {"lt": current_time}}]},
            "limit": 10000,  # Large limit for dry-run counting
            "with_payload": ["namespace", "doc_id", "expires_at"],
            "with_vector": False,
        }

        try:
            response = await client.post(
                f"{config.qdrant_url}/collections/{config.collection_name}/points/scroll",
                json=query_payload,
                timeout=30.0,
            )
            response.raise_for_status()

            data = response.json()
            points = data.get("result", {}).get("points", [])

            logger.info(f"[DRY-RUN] Would delete {len(points)} expired documents")
            for doc in points[:10]:  # Log first 10 for preview
                payload = doc.get("payload", {})
                logger.info(
                    f"[DRY-RUN] Would delete: id={doc['id']}, "
                    f"namespace={payload.get('namespace')}, "
                    f"doc_id={payload.get('doc_id')}, "
                    f"expires_at={payload.get('expires_at')}"
                )

            return {"deleted_count": len(points), "points": points, "dry_run": True}

        except httpx.HTTPError as e:
            logger.error(f"Failed to query expired documents for dry-run: {e}")
            return {"deleted_count": 0, "points": [], "error": str(e)}

    # LIVE mode: First count expired documents, then perform synchronous delete
    
    # Step 1: Count expired documents before deletion
    count_payload = {
        "filter": {"must": [{"key": "expires_at", "range": {"lt": current_time}}]},
        "exact": True  # Get exact count
    }
    
    expected_delete_count = 0
    try:
        count_response = await client.post(
            f"{config.qdrant_url}/collections/{config.collection_name}/points/count",
            json=count_payload,
            timeout=30.0,
        )
        count_response.raise_for_status()
        count_result = count_response.json()
        expected_delete_count = count_result.get("result", {}).get("count", 0)
        
        if expected_delete_count == 0:
            logger.info("No expired documents found to delete")
            return {"deleted_count": 0, "operation_result": {}, "status": "ok"}
            
        logger.info(f"Found {expected_delete_count} expired documents to delete")
        
    except httpx.HTTPError as e:
        logger.error(f"Failed to count expired documents: {e}")
        return {"deleted_count": 0, "error": str(e)}

    # Step 2: Perform synchronous deletion with wait=true
    delete_payload = {
        "filter": {"must": [{"key": "expires_at", "range": {"lt": current_time}}]},
        "wait": True  # Wait for operation to complete synchronously
    }

    try:
        response = await client.post(
            f"{config.qdrant_url}/collections/{config.collection_name}/points/delete?wait=true",
            json=delete_payload,
            timeout=120.0,  # Longer timeout for potentially large deletes
        )
        response.raise_for_status()

        result = response.json()
        operation_result = result.get("result", {})
        
        # For synchronous operations with wait=true, Qdrant should return the actual deleted count
        # Try multiple possible response keys where the deleted count might be stored
        deleted_count = (
            operation_result.get("deleted", 0) or  # Most likely key for deleted count
            operation_result.get("affected", 0) or  # Alternative key
            operation_result.get("count", 0) or     # Another possible key
            expected_delete_count if result.get("status") == "ok" else 0  # Fallback to expected count on success
        )
        
        # Ensure we have a valid integer count
        if not isinstance(deleted_count, int):
            deleted_count = expected_delete_count if result.get("status") == "ok" else 0

        # For immediate feedback, we'll use status from response
        status = result.get("status", "unknown")

        logger.info(
            f"Successfully initiated delete operation for expired documents (status: {status})"
        )

        return {
            "deleted_count": deleted_count if isinstance(deleted_count, int) else 0,
            "operation_result": operation_result,
            "status": status,
        }

    except httpx.HTTPError as e:
        logger.error(f"Failed to delete expired documents by filter: {e}")
        return {"deleted_count": 0, "error": str(e)}


async def cleanup_expired_content(config: CleanupConfig) -> CleanupStats:
    """
    Main cleanup function - finds and removes expired documents using atomic delete-by-filter.

    Args:
        config: Configuration for cleanup operation

    Returns:
        Statistics from cleanup operation
    """
    start_time = datetime.now()
    stats = CleanupStats()

    logger.info(f"Starting TTL cleanup (dry_run={config.dry_run})")

    # Build authentication headers for all requests
    auth_headers = build_auth_headers(config)
    
    async with httpx.AsyncClient(headers=auth_headers) as client:
        try:
            # Perform atomic delete-by-filter operation
            delete_result = await delete_expired_by_filter(client, config)

            if "error" in delete_result:
                stats.errors.append(
                    f"Delete operation failed: {delete_result['error']}"
                )
            else:
                deleted_count = delete_result.get("deleted_count", 0)
                stats.total_deleted = deleted_count
                stats.total_scanned = (
                    deleted_count  # In atomic operation, scanned = deleted
                )
                stats.total_expired = deleted_count

                # Extract namespace information if available (from dry-run or additional query)
                if config.dry_run and "points" in delete_result:
                    for doc in delete_result["points"]:
                        namespace = doc.get("payload", {}).get("namespace")
                        if namespace and namespace not in stats.namespaces_affected:
                            stats.namespaces_affected.append(namespace)
                elif not config.dry_run and deleted_count > 0:
                    # For live mode, we could optionally query for namespace info
                    # but atomic delete doesn't return detailed point info
                    logger.info(
                        f"Atomic delete completed - {deleted_count} documents removed"
                    )

        except Exception as e:
            error_msg = f"Unexpected error during cleanup: {e}"
            logger.error(error_msg)
            stats.errors.append(error_msg)

    # Calculate execution time
    end_time = datetime.now()
    stats.execution_time_seconds = (end_time - start_time).total_seconds()

    logger.info(f"TTL cleanup completed: {stats.model_dump_json(indent=2)}")
    return stats


async def delete_expired_batch(
    client: httpx.AsyncClient, config: CleanupConfig, point_ids: list[str]
) -> bool:
    """
    Delete a batch of expired document points.

    Args:
        client: HTTP client for Qdrant API
        config: Cleanup configuration
        point_ids: List of point IDs to delete

    Returns:
        True if deletion successful, False otherwise
    """
    if config.dry_run:
        logger.info(f"[DRY-RUN] Would delete {len(point_ids)} expired documents")
        return True

    delete_payload = {"points": point_ids}

    try:
        response = await client.post(
            f"{config.qdrant_url}/collections/{config.collection_name}/points/delete",
            json=delete_payload,
            timeout=60.0,
        )
        response.raise_for_status()

        logger.info(f"Successfully deleted {len(point_ids)} expired documents")
        return True

    except httpx.HTTPError as e:
        logger.error(f"Failed to delete batch: {e}")
        return False


def load_config() -> CleanupConfig:
    """Load configuration from environment variables."""
    return CleanupConfig(
        qdrant_url=os.getenv("QDRANT_URL", "http://localhost:6333"),
        collection_name=os.getenv("QDRANT_COLLECTION", "hx_rag_default"),
        batch_size=int(os.getenv("CLEANUP_BATCH_SIZE", "1000")),
        admin_key=os.getenv("HX_ADMIN_KEY"),
    )


async def main():
    """Main entry point for TTL cleanup script."""
    parser = argparse.ArgumentParser(description="TTL Cleanup for Qdrant Vector Store")
    parser.add_argument(
        "--dry-run", action="store_true", help="Preview what would be deleted"
    )
    parser.add_argument(
        "--batch-size", type=int, default=1000, help="Batch size for processing"
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Enable verbose logging"
    )

    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Load configuration
    config = load_config()
    config.dry_run = args.dry_run
    config.batch_size = args.batch_size

    try:
        # Run cleanup
        stats = await cleanup_expired_content(config)

        # Output results
        print("\n=== TTL Cleanup Results ===")
        print(f"Mode: {'DRY-RUN' if config.dry_run else 'LIVE'}")
        print(f"Documents scanned: {stats.total_scanned}")
        print(f"Documents expired: {stats.total_expired}")
        print(f"Documents deleted: {stats.total_deleted}")
        print(
            f"Namespaces affected: {', '.join(stats.namespaces_affected) if stats.namespaces_affected else 'None'}"
        )
        print(f"Execution time: {stats.execution_time_seconds:.2f}s")

        if stats.errors:
            print(f"Errors: {len(stats.errors)}")
            for error in stats.errors:
                print(f"  - {error}")

        # Exit with error if cleanup failed
        if stats.errors:
            sys.exit(1)

    except Exception as e:
        logger.error(f"TTL cleanup failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
