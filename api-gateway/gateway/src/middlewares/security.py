# /opt/HX-Infrastructure-/api-gateway/gateway/src/middlewares/security.py
import hmac
import logging
import os
from pathlib import Path
from typing import Any

from fastapi import Request
from fastapi.responses import JSONResponse

from .base import MiddlewareBase


class SecurityMiddleware(MiddlewareBase):
    def __init__(self):
        super().__init__()
        # Load master key strictly from environment variables
        self.master_key = os.getenv("HX_MASTER_KEY") or os.getenv("MASTER_KEY")

        # Check for development-only configuration
        dev_config_path = os.getenv("HX_DEV_CONFIG_PATH")
        allow_dev_key = os.getenv("HX_ALLOW_DEV_KEY", "").lower() in (
            "true",
            "1",
            "yes",
        )

        if not self.master_key:
            if dev_config_path:
                # Validate and sanitize the development config path to prevent path traversal
                try:
                    # Convert to absolute path and resolve any symbolic links
                    config_path = Path(dev_config_path).resolve()

                    # Security validation: ensure the path is within allowed directories
                    allowed_base_dirs = [
                        Path("/opt/HX-Infrastructure-").resolve(),
                        Path("/etc/hx-gateway").resolve(),
                        Path.home() / ".hx-gateway",
                        Path("/tmp/hx-gateway-dev").resolve(),
                    ]

                    # Check if the resolved path is within any allowed directory
                    path_is_safe = any(
                        str(config_path).startswith(str(allowed_dir))
                        for allowed_dir in allowed_base_dirs
                        if allowed_dir.exists()
                        or str(config_path).startswith(str(allowed_dir))
                    )

                    if not path_is_safe:
                        raise RuntimeError(
                            f"Security error: Development config path '{dev_config_path}' is not within allowed directories. "
                            f"Allowed base paths: {[str(d) for d in allowed_base_dirs]}"
                        )

                    # Additional validation: ensure it's a regular file, not a directory or device
                    if config_path.exists() and not config_path.is_file():
                        raise RuntimeError(
                            f"Security error: '{config_path}' is not a regular file"
                        )

                    # Check file size to prevent reading large files
                    if (
                        config_path.exists() and config_path.stat().st_size > 10240
                    ):  # 10KB limit
                        raise RuntimeError(
                            f"Security error: Config file '{config_path}' is too large (max 10KB)"
                        )

                    if config_path.exists():
                        # Load from development config file with secure reading
                        with open(config_path, encoding="utf-8") as f:
                            content = f.read(10240)  # Limit read size
                            for line in content.splitlines():
                                line = line.strip()
                                if line.startswith("MASTER_KEY="):
                                    key_value = line.split("=", 1)[1].strip()
                                    # Remove quotes if present
                                    if (
                                        key_value.startswith('"')
                                        and key_value.endswith('"')
                                    ) or (
                                        key_value.startswith("'")
                                        and key_value.endswith("'")
                                    ):
                                        key_value = key_value[1:-1]
                                    self.master_key = key_value
                                    break

                        if self.master_key:
                            logging.warning(
                                f"⚠️  DEVELOPMENT MODE: Using master key from {config_path}. "
                                "This is NOT secure for production use!"
                            )
                        else:
                            raise RuntimeError(
                                f"No MASTER_KEY found in development config file: {config_path}"
                            )

                except (OSError, ValueError) as e:
                    raise RuntimeError(
                        f"Failed to read development config file '{dev_config_path}': {e}"
                    )
                except Exception as e:
                    raise RuntimeError(
                        f"Security error accessing config file '{dev_config_path}': {e}"
                    )
            elif allow_dev_key:
                # Only allowed if explicitly enabled for development
                self.master_key = "sk-hx-dev-1234"
                logging.warning(
                    "⚠️  DEVELOPMENT MODE: Using hardcoded development key. "
                    "Set HX_MASTER_KEY or MASTER_KEY environment variable for production use!"
                )
            else:
                raise RuntimeError(
                    "No master key configured. Set HX_MASTER_KEY or MASTER_KEY environment variable, "
                    "or provide HX_DEV_CONFIG_PATH for development, or set HX_ALLOW_DEV_KEY=true for dev mode."
                )

    async def process(self, context: dict[str, Any]) -> dict[str, Any]:
        request: Request = context["request"]

        # Allow health endpoints without auth
        if request.url.path in ("/healthz", "/livez", "/readyz"):
            return context

        # Get authorization header safely
        auth_header = request.headers.get("authorization", "")

        # Extract token with case-insensitive scheme check but preserve token case
        if not auth_header.lower().startswith("bearer "):
            context["response"] = JSONResponse(
                {"error": "Unauthorized"},
                status_code=401,
                headers={"WWW-Authenticate": "Bearer"},
            )
            return context

        # Extract token (preserve original case)
        provided_token = (
            auth_header.split(" ", 1)[1] if len(auth_header.split(" ", 1)) > 1 else ""
        )

        # Use constant-time comparison to prevent timing attacks
        if not provided_token or not hmac.compare_digest(
            provided_token, self.master_key
        ):
            context["response"] = JSONResponse(
                {"error": "Unauthorized"},
                status_code=401,
                headers={"WWW-Authenticate": "Bearer"},
            )
            return context

        return context
