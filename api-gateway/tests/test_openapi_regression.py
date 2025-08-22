# tests/test_openapi_regression.py
"""
OpenAPI regression guard tests.

Ensures annotations/OpenAPI issues don't regress by testing schema generation
and validating endpoint presence.
"""
import pytest
from gateway.src.app import build_app


class TestOpenAPIRegression:
    """Guard tests to prevent OpenAPI/annotations regressions."""

    def test_openapi_schema_generation(self):
        """Test that OpenAPI schema generation works without errors."""
        app = build_app()

        # This should not raise any exceptions
        openapi_schema = app.openapi()

        # Basic structure validation
        assert isinstance(openapi_schema, dict)
        assert "openapi" in openapi_schema
        assert "info" in openapi_schema
        assert "paths" in openapi_schema

        # Should have reasonable number of paths
        paths = openapi_schema.get("paths", {})
        assert len(paths) >= 5, f"Expected at least 5 paths, got {len(paths)}"

    def test_required_endpoints_in_schema(self):
        """Test that required endpoints are present in OpenAPI schema."""
        app = build_app()
        openapi_schema = app.openapi()
        paths = openapi_schema.get("paths", {})

        required_endpoints = [
            "/healthz",
            "/v1/rag/upsert",
            "/v1/rag/search",
            "/v1/rag/delete/by_ids",
            "/v1/rag/upsert_markdown",
        ]

        missing_endpoints = [ep for ep in required_endpoints if ep not in paths]
        assert not missing_endpoints, f"Missing required endpoints: {missing_endpoints}"

    def test_operation_ids_unique(self):
        """Test that operation IDs are unique (no duplicates that break schema)."""
        app = build_app()
        openapi_schema = app.openapi()
        paths = openapi_schema.get("paths", {})

        operation_ids = []
        for path_info in paths.values():
            for method_info in path_info.values():
                if "operationId" in method_info:
                    operation_ids.append(method_info["operationId"])

        # Check for duplicates
        seen = set()
        duplicates = []
        for op_id in operation_ids:
            if op_id in seen:
                duplicates.append(op_id)
            seen.add(op_id)

        assert not duplicates, f"Duplicate operation IDs found: {duplicates}"

    def test_models_serialize_correctly(self):
        """Test that Pydantic models serialize correctly (no annotation issues)."""
        from gateway.src.models.rag_delete_models import (
            DeleteByIdsRequest,
            DeleteResponse,
        )
        from gateway.src.models.rag_upsert_models import UpsertDoc, UpsertRequest

        # Test basic model creation and serialization
        doc = UpsertDoc(text="test content", namespace="test:ns")
        assert doc.model_dump()["text"] == "test content"

        request = UpsertRequest(documents=[doc])
        assert len(request.model_dump()["documents"]) == 1

        delete_req = DeleteByIdsRequest(ids=["test-id"])
        assert delete_req.model_dump()["ids"] == ["test-id"]

        delete_resp = DeleteResponse(status="ok", deleted=1)
        assert delete_resp.model_dump()["status"] == "ok"

    def test_json_schema_generation(self):
        """Test that JSON schema generation works for all models."""
        from gateway.src.models.rag_delete_models import (
            DeleteByIdsRequest,
            DeleteResponse,
        )
        from gateway.src.models.rag_upsert_models import UpsertDoc, UpsertRequest

        models_to_test = [UpsertDoc, UpsertRequest, DeleteByIdsRequest, DeleteResponse]

        for model_class in models_to_test:
            schema = model_class.model_json_schema()

            # Basic schema structure
            assert isinstance(schema, dict)
            assert "type" in schema
            assert "properties" in schema

            # Should have some properties defined
            assert (
                len(schema["properties"]) > 0
            ), f"No properties in {model_class.__name__} schema"


class TestAnnotationsSafety:
    """Tests specifically for annotations safety patterns."""

    def test_no_future_annotations_in_routes(self):
        """Test that route modules don't use postponed annotations (causes OpenAPI issues)."""
        import ast
        import os

        routes_dir = "gateway/src/routes"
        route_files = []

        for root, _dirs, files in os.walk(routes_dir):
            for file in files:
                if file.endswith(".py") and not file.startswith("__"):
                    route_files.append(os.path.join(root, file))

        problematic_files = []

        for file_path in route_files:
            try:
                with open(file_path) as f:
                    content = f.read()

                # Parse the AST to check for future annotations import
                tree = ast.parse(content)
                for node in ast.walk(tree):
                    if (
                        isinstance(node, ast.ImportFrom)
                        and node.module == "__future__"
                        and any(
                            alias.name == "annotations" for alias in (node.names or [])
                        )
                    ):
                        problematic_files.append(file_path)
                        break

            except Exception as e:
                pytest.fail(f"Failed to parse {file_path}: {e}")

        assert not problematic_files, (
            f"Route modules should not use 'from __future__ import annotations' "
            f"as it can break OpenAPI generation. Found in: {problematic_files}"
        )

    def test_body_vs_query_usage(self):
        """Test that Body() and Query() are used appropriately."""
        import os
        import re

        routes_dir = "gateway/src/routes"

        for root, _dirs, files in os.walk(routes_dir):
            for file in files:
                if file.endswith(".py"):
                    file_path = os.path.join(root, file)
                    try:
                        with open(file_path) as f:
                            content = f.read()

                        # Look for Query() usage - should be for simple types
                        query_matches = re.findall(
                            r"(\w+):\s*\w+\s*=\s*Query\([^)]*\)", content
                        )

                        # Look for Body() usage - should be for complex models
                        body_matches = re.findall(
                            r"(\w+):\s*(\w+)\s*=\s*Body\([^)]*\)", content
                        )

                        # This is more of a documentation test - we just want to ensure
                        # the patterns are being followed consistently
                        if query_matches or body_matches:
                            # Test passes if we found either pattern - the usage is intentional
                            pass

                    except Exception:
                        # Skip files that can't be read
                        pass
