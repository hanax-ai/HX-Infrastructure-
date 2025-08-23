#!/usr/bin/env python3
"""
Safe AST-based script to fix imports in gateway/src/app.py.

This script replaces the brittle sed commands with proper AST manipulation to:
1. Add 'import os' if not present
2. Add Response to the FastAPI import if not present
3. Rename starlette Response import to 'Response as StarResponse'

The script is idempotent and safe to run multiple times.
"""

import ast
import sys
from pathlib import Path
from typing import List, Union


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


class ImportTransformer(ast.NodeTransformer):
    """AST transformer to safely modify imports."""
    
    def __init__(self):
        self.has_os_import = False
        self.has_fastapi_response = False
        self.has_starlette_renamed = False
        self.modified = False
    
    def visit_Import(self, node: ast.Import) -> ast.Import:
        """Handle 'import os' statements."""
        for alias in node.names:
            if alias.name == 'os':
                self.has_os_import = True
                print("✅ Found existing 'import os'")
        return node
    
    def visit_ImportFrom(self, node: ast.ImportFrom) -> ast.ImportFrom:
        """Handle 'from module import ...' statements."""
        if node.module == 'fastapi':
            # Check if Response is already imported from fastapi
            imported_names = [alias.name for alias in node.names]
            if 'Response' not in imported_names and ('FastAPI' in imported_names or 'Request' in imported_names):
                # Add Response to the import
                print("✅ Adding Response to FastAPI import")
                node.names.append(ast.alias(name='Response', asname=None))
                self.has_fastapi_response = True
                self.modified = True
            elif 'Response' in imported_names:
                self.has_fastapi_response = True
                print("✅ Found existing Response in FastAPI import")
        
        elif node.module == 'starlette.responses':
            # Check and fix starlette.responses import
            for i, alias in enumerate(node.names):
                if alias.name == 'Response' and alias.asname != 'StarResponse':
                    print("✅ Renaming starlette Response to StarResponse")
                    node.names[i] = ast.alias(name='Response', asname='StarResponse')
                    self.has_starlette_renamed = True
                    self.modified = True
                elif alias.name == 'Response' and alias.asname == 'StarResponse':
                    self.has_starlette_renamed = True
                    print("✅ Found existing 'Response as StarResponse'")
        
        return node


def process_app_py(app_py_path: Path):
    """Process the app.py file to fix imports using AST manipulation."""
    try:
        content = app_py_path.read_text()
        
        # Parse the AST
        tree = ast.parse(content)
        
        # Transform the imports
        transformer = ImportTransformer()
        new_tree = transformer.visit(tree)
        
        # Add missing imports at the top
        new_imports = []
        
        if not transformer.has_os_import:
            print("✅ Adding 'import os'")
            new_imports.append(ast.Import(names=[ast.alias(name='os', asname=None)]))
            transformer.modified = True
        
        # Insert new imports at the beginning if needed
        if new_imports:
            new_tree.body = new_imports + new_tree.body
        
        if not transformer.modified:
            print("✅ All imports are already correctly configured")
            return
        
        # Convert AST back to source code
        try:
            # Try to use ast.unparse (Python 3.9+)
            new_content = ast.unparse(new_tree)
        except AttributeError:
            # Fallback for older Python versions
            print("❌ ast.unparse not available. Need Python 3.9+ or astor package")
            sys.exit(1)
        
        # Create backup
        backup_path = app_py_path.with_suffix(".py.backup-imports")
        backup_path.write_text(content)
        print(f"✅ Created backup at {backup_path}")
        
        # Write the new content
        app_py_path.write_text(new_content)
        print(f"✅ Updated imports in {app_py_path}")
        
    except Exception as e:
        print(f"❌ Failed to process {app_py_path}: {e}")
        sys.exit(1)


def main():
    """Main function to fix imports in the gateway app."""
    print("🔧 Fixing imports in HX API Gateway using AST manipulation...")
    
    # Find the app.py file
    app_py_path = find_gateway_app_py()
    if not app_py_path:
        print("❌ Could not find gateway/src/app.py file")
        print("Please run this script from the repository root or ensure the file exists")
        sys.exit(1)
    
    print(f"📁 Found app.py at: {app_py_path}")
    
    # Process app.py
    process_app_py(app_py_path)
    
    print("\n✅ Import fixes complete!")
    print("The following transformations were applied:")
    print("  - Added 'import os' if missing")
    print("  - Added Response to FastAPI import if missing")
    print("  - Renamed starlette Response to 'Response as StarResponse'")


if __name__ == "__main__":
    main()
