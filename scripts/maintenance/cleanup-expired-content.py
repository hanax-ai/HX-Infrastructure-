#!/usr/bin/env python3
"""
TTL Cleanup Script - Removes expired documents from Qdrant
Designed for nightly cron execution to maintain clean vector store.

Usage:
    python3 cleanup-expired-content.py [--dry-run] [--batch-size=1000]
"""

import os
import sys
import json
import asyncio
import logging
from datetime import datetime, timezone
from typing import List, Optional, Dict, Any
import argparse

import httpx
from pydantic import BaseModel

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('/var/log/hx-gateway-ml/ttl-cleanup.log')
    ]
)
logger = logging.getLogger(__name__)


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
    namespaces_affected: List[str] = []
    errors: List[str] = []
    execution_time_seconds: float = 0.0


async def get_expired_documents(
    client: httpx.AsyncClient,
    config: CleanupConfig,
    offset: int = 0
) -> List[Dict[str, Any]]:
    """
    Query Qdrant for documents with expired TTL.
    
    Args:
        client: HTTP client for Qdrant API
        config: Cleanup configuration
        offset: Pagination offset
        
    Returns:
        List of expired document point IDs and metadata
    """
    current_time = datetime.now(timezone.utc).isoformat()
    
    # Qdrant scroll query to find expired documents
    query_payload = {
        "filter": {
            "must": [
                {
                    "key": "expires_at",
                    "range": {
                        "lt": current_time
                    }
                }
            ]
        },
        "limit": config.batch_size,
        "offset": offset,
        "with_payload": ["namespace", "doc_id", "expires_at", "created_at"],
        "with_vector": False
    }
    
    try:
        response = await client.post(
            f"{config.qdrant_url}/collections/{config.collection_name}/points/scroll",
            json=query_payload,
            timeout=30.0
        )
        response.raise_for_status()
        
        data = response.json()
        return data.get("result", {}).get("points", [])
        
    except httpx.HTTPError as e:
        logger.error(f"Failed to query expired documents: {e}")
        return []


async def delete_expired_batch(
    client: httpx.AsyncClient,
    config: CleanupConfig,
    point_ids: List[str]
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
    
    delete_payload = {
        "points": point_ids
    }
    
    try:
        response = await client.post(
            f"{config.qdrant_url}/collections/{config.collection_name}/points/delete",
            json=delete_payload,
            timeout=60.0
        )
        response.raise_for_status()
        
        logger.info(f"Successfully deleted {len(point_ids)} expired documents")
        return True
        
    except httpx.HTTPError as e:
        logger.error(f"Failed to delete batch: {e}")
        return False


async def cleanup_expired_content(config: CleanupConfig) -> CleanupStats:
    """
    Main cleanup function - finds and removes expired documents.
    
    Args:
        config: Cleanup configuration
        
    Returns:
        Statistics from cleanup operation
    """
    start_time = datetime.now()
    stats = CleanupStats()
    
    logger.info(f"Starting TTL cleanup (dry_run={config.dry_run})")
    
    async with httpx.AsyncClient() as client:
        offset = 0
        
        while True:
            # Get batch of expired documents
            expired_docs = await get_expired_documents(client, config, offset)
            
            if not expired_docs:
                logger.info("No more expired documents found")
                break
            
            stats.total_scanned += len(expired_docs)
            stats.total_expired += len(expired_docs)
            
            # Extract point IDs and track namespaces
            point_ids = []
            for doc in expired_docs:
                point_ids.append(doc["id"])
                
                namespace = doc.get("payload", {}).get("namespace")
                if namespace and namespace not in stats.namespaces_affected:
                    stats.namespaces_affected.append(namespace)
            
            # Log expiration details
            for doc in expired_docs:
                payload = doc.get("payload", {})
                logger.info(
                    f"Expired document: id={doc['id']}, "
                    f"namespace={payload.get('namespace')}, "
                    f"doc_id={payload.get('doc_id')}, "
                    f"expires_at={payload.get('expires_at')}"
                )
            
            # Delete batch
            if await delete_expired_batch(client, config, point_ids):
                stats.total_deleted += len(point_ids)
            else:
                stats.errors.append(f"Failed to delete batch at offset {offset}")
            
            # Continue pagination
            offset += config.batch_size
    
    # Calculate execution time
    end_time = datetime.now()
    stats.execution_time_seconds = (end_time - start_time).total_seconds()
    
    logger.info(f"TTL cleanup completed: {stats.model_dump_json(indent=2)}")
    return stats


def load_config() -> CleanupConfig:
    """Load configuration from environment variables."""
    return CleanupConfig(
        qdrant_url=os.getenv("QDRANT_URL", "http://localhost:6333"),
        collection_name=os.getenv("QDRANT_COLLECTION", "hx_embeddings"),
        batch_size=int(os.getenv("CLEANUP_BATCH_SIZE", "1000")),
        admin_key=os.getenv("HX_ADMIN_KEY")
    )


async def main():
    """Main entry point for TTL cleanup script."""
    parser = argparse.ArgumentParser(description="TTL Cleanup for Qdrant Vector Store")
    parser.add_argument("--dry-run", action="store_true", help="Preview what would be deleted")
    parser.add_argument("--batch-size", type=int, default=1000, help="Batch size for processing")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable verbose logging")
    
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
        print(f"\n=== TTL Cleanup Results ===")
        print(f"Mode: {'DRY-RUN' if config.dry_run else 'LIVE'}")
        print(f"Documents scanned: {stats.total_scanned}")
        print(f"Documents expired: {stats.total_expired}")
        print(f"Documents deleted: {stats.total_deleted}")
        print(f"Namespaces affected: {', '.join(stats.namespaces_affected) if stats.namespaces_affected else 'None'}")
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
