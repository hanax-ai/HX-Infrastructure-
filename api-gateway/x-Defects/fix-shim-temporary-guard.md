# Test Environment Setup Guide

> **Purpose**: To ensure the test suite runs against the correct code, dependencies, and configuration by (1) moving to the repo root for reliable relative paths, (2) activating the project’s virtualenv to pin package versions, (3) setting `PYTHONPATH` so `src/...` imports resolve to our gateway code, and (4) exporting the expected `LITELLM_MASTER_KEY` so auth middleware behaves as tests assume—then executing `pytest` in that controlled environment.

---

> **Status**: ✅ Verified & Executed
> **Last Run**: August 21, 2025
> **Outcome**: All 16 tests passed successfully.

## 1. Go to the project root

This ensures that all relative paths used by tests (e.g., `gateway/src/...`, `gateway/tests/...`) resolve correctly.

```bash
cd /opt/HX-Infrastructure-/api-gateway
```

### Quick Check

You should see the `gateway` directory and its subdirectories. If not, you’re in the wrong location.

```bash
ls -ld gateway gateway/src gateway/tests
```

## 2. Activate the project’s virtual environment

This switches your shell to use the project’s specific Python interpreter and installed packages. Your shell prompt should change to include `(venv)`.

```bash
source gateway/venv/bin/activate
```

### If Activation Fails

Ensure the virtual environment exists.

```bash
# Check for the Python executable in the venv
ls gateway/venv/bin/python
```

If it doesn’t exist, create it and install the required dependencies:

```bash
python3 -m venv gateway/venv
source gateway/venv/bin/activate
pip install -r gateway/requirements.lock
```

## 3. Set `PYTHONPATH`

This step tells Python where to find the application's source modules (`src/...`), which is crucial for resolving imports correctly.

```bash
export PYTHONPATH=/opt/HX-Infrastructure-/api-gateway/gateway
```

> **Note**: If you see `ModuleNotFoundError: No module named 'src'`, confirm that you ran the `export` command in the same shell where you are running `pytest`.

## 4. Provide Master Key for Tests

The security middleware in the pipeline requires this environment variable for authentication tests.

```bash
export LITELLM_MASTER_KEY="test-master-key"
```

> **Tip**: This is for local testing only. Do not reuse real production keys in tests.

## 5. Run the Test Suite

Execute `pytest` to run all tests located in the `gateway/tests` directory. The `-q` flag provides a quiet, summary-level output.

```bash
pytest -q gateway/tests
```

### Useful Variants

- **Run a single test file:**
  ```bash
  pytest -q gateway/tests/test_pipeline.py
  ```

- **Run a specific test function:**
  ```bash
  pytest -q gateway/tests/test_pipeline.py::test_full_pipeline_smoke_test_success
  ```

- **Show `print()` and log output:**
  ```bash
  pytest -s gateway/tests
  ```

- **Show the slowest running tests:**
  ```bash
  pytest -q --durations=10 gateway/tests
  ```

---

## Common Issues & Quick Fixes

### A) Asyncio Warnings

- **Symptom**: `PytestUnknownMarkWarning: asyncio` or `PytestUnhandledCoroutineWarning`.
- **Fix**: Ensure the `pytest-asyncio` plugin is installed.
  ```bash
  pip install "pytest-asyncio>=0.23"
  ```
- **(Optional)** Add a `pytest.ini` file to the root to silence deprecation warnings:
  ```ini
  [pytest]
  asyncio_default_fixture_loop_scope = function
  ```

### B) Import Errors (`ModuleNotFoundError`)

- **Fix**: Ensure Step 3 was completed correctly and `PYTHONPATH` is set.
  ```bash
  echo $PYTHONPATH
  # Expected output: /opt/HX-Infrastructure-/api-gateway/gateway
  ```
- **Verify**: Confirm that the source files exist (e.g., `gateway/src/app.py`).

### C) DB Guard Constructor Mismatch

- **Symptom**: `TypeError: DBGuardMiddleware.__init__() missing ...`
- **Cause**: The `GatewayPipeline` is instantiating `DBGuardMiddleware` with the wrong arguments.
- **Fix**: This was resolved by applying the compatibility shim to `gateway_pipeline.py`, which handles multiple constructor signatures gracefully.

### D) Messy `pip` Leftovers

- **Symptom**: Warnings about temporary files like `~ttpx` or `~*.dist-info`.
- **Fix**: These are safe to remove. They are typically left over from interrupted package installations.
  ```bash
  VENV=/opt/HX-Infrastructure-/api-gateway/gateway/venv
  find "$VENV/lib/python3.12/site-packages" -maxdepth 1 -type d -name '~*' -print -exec rm -rf {} +
  pip check || true
  ```

---

## Sanity Checklist

Before running tests, ensure:

- ✅ `(venv)` is visible in your shell prompt.
- ✅ `echo $PYTHONPATH` prints `/opt/HX-Infrastructure-/api-gateway/gateway`.
- ✅ `pytest -q gateway/tests` runs and reports results.
