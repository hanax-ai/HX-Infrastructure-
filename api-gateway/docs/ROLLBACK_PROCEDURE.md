# Rollback Procedure: Gateway v2.0 to v1.0

**Document Version**: 1.0  
**Last Updated**: August 21, 2025  
**Applies to**: Reverting the API Gateway from the `GatewayPipeline` architecture (v2.0) back to the monolithic proxy (v1.0).

---

## 1. Overview

This document outlines the emergency procedure to roll back the HX API Gateway from the new, modular `GatewayPipeline` architecture to the previous stable, monolithic version.

This procedure should only be used if a critical, unresolvable issue is discovered in the v2.0 deployment that severely impacts production traffic. The primary change involves reverting the application's entrypoint from `gateway.src.app:build_app` back to the original `gateway.main:app`.

**Estimated Time to Complete**: 10-15 minutes.

## 2. Pre-requisites

- **SSH Access**: You must have `sudo` access to the server hosting the API Gateway.
- **Code Versioning**: This guide assumes that the previous version of the application code is available via `git`. You will need the commit hash of the last stable v1.0 deployment. If `git` is not available, a manual code revert is required, which is higher risk.

## 3. Rollback Steps

### Step 1: Stop the Live Service

To prevent errors and ensure a clean state change, stop the `hx-gateway-ml` service.

```bash
# Stop the gateway service
sudo systemctl stop hx-gateway-ml

# Verify the service is stopped
sudo systemctl status hx-gateway-ml
# Expected output should show the service as "inactive (dead)"
```

### Step 2: Revert Application Code via Git

The safest method is to use `git` to check out the specific files that were changed for the v2.0 release. The key files are the application entrypoints and the pipeline itself.

**Identify the last stable v1.0 commit hash.** For this example, let's assume the hash is `c1a2b3d4`.

```bash
# Navigate to the application directory
cd /opt/HX-Infrastructure-/api-gateway/

# Revert the main application files to the v1.0 state
# This command restores the old main.py and removes the new v2.0 files.
# Replace 'c1a2b3d4' with the actual commit hash for v1.0.
git checkout c1a2b3d4 -- gateway/src/main.py gateway/src/app.py gateway/src/gateway_pipeline.py gateway/src/middlewares/

# It is also recommended to revert the documentation to avoid confusion
git checkout c1a2b3d4 -- README.md gateway/README.md docs/architecture.md
```
**Note**: If you don't have the commit hash, you would need to manually replace the contents of `app.py` with the old `main.py` logic and ensure the `systemd` service points to the correct file and object.

### Step 3: Revert the `systemd` Service Configuration

The `systemd` service file defines how the application is run. The `ExecStart` directive must be changed back to point to the v1.0 entrypoint.

```bash
# Open the service file for editing
sudo nano /etc/systemd/system/hx-gateway-ml.service
```

Find the `[Service]` section and locate the `ExecStart` line.

**Change this (v2.0):**
```ini
ExecStart=/opt/HX-Infrastructure-/api-gateway/gateway/venv/bin/uvicorn gateway.src.app:build_app --factory --host 0.0.0.0 --port 4010 --root-path /opt/HX-Infrastructure-/api-gateway
```

**To this (v1.0):**
```ini
ExecStart=/opt/HX-Infrastructure-/api-gateway/gateway/venv/bin/uvicorn gateway.main:app --host 0.0.0.0 --port 4010 --root-path /opt/HX-Infrastructure-/api-gateway
```
Save and close the file.

### Step 4: Reload `systemd` and Restart the Service

After modifying the service file, you must reload the `systemd` daemon to apply the changes.

```bash
# Reload the systemd configuration
sudo systemctl daemon-reload

# Restart the gateway service with the old configuration
sudo systemctl start hx-gateway-ml
```

## 4. Verification

### Step 5: Verify the Service Status and Functionality

Confirm that the service has started successfully and is running the old code.

```bash
# Check the service status
sudo systemctl status hx-gateway-ml
# Expected: Active (running)

# Check the application logs for any startup errors
sudo journalctl -u hx-gateway-ml -n 50 --no-pager

# Perform a health check
curl -s http://127.0.0.1:4010/healthz | jq .
# Expected (v1.0 response): {"ok": true, "note": "HX wrapper – proxy mode"}
```

If the health check returns the `proxy mode` note, the rollback to v1.0 was successful. The gateway is now operating as a monolithic proxy.

## 5. Post-Rollback Actions

- **Create a Post-Mortem**: Document the reason for the rollback to prevent future issues.
- **Communicate Status**: Inform relevant stakeholders that the rollback has been completed.
- **Freeze Deployments**: Pause any further deployments until the v2.0 issues are fully resolved and tested.
