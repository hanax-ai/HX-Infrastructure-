#!/usr/bin/env python3
"""
Idempotent script to add Prometheus metrics support to the FastAPI gateway.

This script safely adds:
1. Prometheus imports (generate_latest, CONTENT_TYPE_LATEST)
2. /metrics endpoint handler next to /healthz
3. Creates metrics.py module if it doesn't exist

The script is idempotent - it can be run multiple times safely.
"""

import ast
import os
import sys
from pathlib import Path


def find_gateway_app_py():
    """Find the gateway/src/app.py file from various possible locations."""
    possible_paths = [
        Path("api-gateway/gateway/src/app.py"),
        Path("gateway/src/app.py"),
        Path("../gateway/src/app.py"),
        Path("../../api-gateway/gateway/src/app.py"),
    ]
    
    for path in possible_paths:
        if path.exists():
            return path.resolve()
    
    # Try relative to script location
    script_dir = Path(__file__).parent
    repo_root = script_dir.parent  # /opt/HX-Infrastructure-
    gateway_path = repo_root / "api-gateway" / "gateway" / "src" / "app.py"
    
    if gateway_path.exists():
        return gateway_path
    
    return None


def create_metrics_module(gateway_src_dir: Path):
    """Create the metrics.py module if it doesn't exist."""
    metrics_path = gateway_src_dir / "metrics.py"
    
    if metrics_path.exists():
        print(f"✅ Metrics module already exists at {metrics_path}")
        return
    
    metrics_content = '''from __future__ import annotations
from prometheus_client import Counter, Histogram

rag_upserts = Counter("rag_upserts_total", "Total RAG upsert requests", ["result"])
rag_deletes = Counter("rag_deletes_total", "Total RAG delete requests", ["result", "mode"])
rag_search  = Counter("rag_search_total",  "Total RAG search requests",  ["result", "path"])

embed_latency = Histogram("rag_embedding_seconds", "Embedding call latency (s)")
qdrant_latency = Histogram("rag_qdrant_seconds", "Qdrant call latency (s)", ["op"])
'''
    
    try:
        metrics_path.write_text(metrics_content)
        print(f"✅ Created metrics module at {metrics_path}")
    except Exception as e:
        print(f"❌ Failed to create metrics module: {e}")
        sys.exit(1)


def has_prometheus_imports(content: str) -> bool:
    """Check if prometheus imports are already present."""
    return (
        "from prometheus_client import" in content and
        "generate_latest" in content and
        "CONTENT_TYPE_LATEST" in content
    )


def has_metrics_endpoint(content: str) -> bool:
    """Check if /metrics endpoint is already defined."""
    return '@app.get("/metrics")' in content or "@app.get('/metrics')" in content


def add_prometheus_imports(lines: list[str]) -> list[str]:
    """Add prometheus imports to the build_app function if not present."""
    new_lines = []
    imports_added = False
    
    for i, line in enumerate(lines):
        new_lines.append(line)
        
        # Look for the build_app function definition
        if "def build_app() -> FastAPI:" in line and not imports_added:
            # Add the imports right after the function definition
            new_lines.append("    from prometheus_client import generate_latest, CONTENT_TYPE_LATEST")
            new_lines.append("")
            imports_added = True
            print("✅ Added Prometheus imports to build_app function")
    
    return new_lines


def add_metrics_endpoint(lines: list[str]) -> list[str]:
    """Add /metrics endpoint after the /healthz endpoint."""
    new_lines = []
    metrics_added = False
    
    i = 0
    while i < len(lines):
        line = lines[i]
        new_lines.append(line)
        
        # Look for the healthz endpoint definition
        if '@app.get("/healthz")' in line and not metrics_added:
            # Add the healthz function
            i += 1
            if i < len(lines):
                new_lines.append(lines[i])  # async def healthz():
            i += 1
            if i < len(lines):
                new_lines.append(lines[i])  # return {"ok": True}
            
            # Add blank line and metrics endpoint
            new_lines.append("")
            new_lines.append('    @app.get("/metrics")')
            new_lines.append("    async def metrics():")
            new_lines.append("        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)")
            
            metrics_added = True
            print("✅ Added /metrics endpoint after /healthz")
        else:
            i += 1
    
    return new_lines


def process_app_py(app_py_path: Path):
    """Process the app.py file to add metrics support."""
    try:
        content = app_py_path.read_text()
        lines = content.splitlines()
        
        # Check what's already present
        has_imports = has_prometheus_imports(content)
        has_endpoint = has_metrics_endpoint(content)
        
        if has_imports and has_endpoint:
            print("✅ Prometheus metrics support already fully configured")
            return
        
        # Make modifications
        modified = False
        
        if not has_imports:
            lines = add_prometheus_imports(lines)
            modified = True
        else:
            print("✅ Prometheus imports already present")
        
        if not has_endpoint:
            lines = add_metrics_endpoint(lines)
            modified = True
        else:
            print("✅ /metrics endpoint already present")
        
        if modified:
            # Write back the modified content
            new_content = "\n".join(lines)
            
            # Validate the syntax before writing
            try:
                ast.parse(new_content)
            except SyntaxError as e:
                print(f"❌ Generated content has syntax errors: {e}")
                sys.exit(1)
            
            # Create backup
            backup_path = app_py_path.with_suffix(".py.backup")
            backup_path.write_text(content)
            print(f"✅ Created backup at {backup_path}")
            
            # Write the new content
            app_py_path.write_text(new_content)
            print(f"✅ Updated {app_py_path}")
        
    except Exception as e:
        print(f"❌ Failed to process {app_py_path}: {e}")
        sys.exit(1)


def main():
    """Main function to add metrics support to the gateway."""
    print("🔧 Adding Prometheus metrics support to HX API Gateway...")
    
    # Find the app.py file
    app_py_path = find_gateway_app_py()
    if not app_py_path:
        print("❌ Could not find gateway/src/app.py file")
        print("Please run this script from the repository root or ensure the file exists")
        sys.exit(1)
    
    print(f"📁 Found app.py at: {app_py_path}")
    
    # Create metrics module
    gateway_src_dir = app_py_path.parent
    create_metrics_module(gateway_src_dir)
    
    # Process app.py
    process_app_py(app_py_path)
    
    print("\n✅ Metrics support setup complete!")
    print("The gateway now includes:")
    print("  - Prometheus metrics module (gateway/src/metrics.py)")
    print("  - /metrics endpoint for Prometheus scraping")
    print("  - Required imports in the FastAPI app")


if __name__ == "__main__":
    main()
