# ORC Test Environment Configuration

## Overview

This directory contains test configuration templates for the ORC (Orchestrator) node testing framework.

## Environment Configuration

### Template File

- **`test.env.example`**: Template showing the expected format for test environment variables

### Usage

1. **Copy the template:**
   ```bash
   cp test.env.example test.env
   ```

2. **Customize for your environment:**
   ```bash
   # Edit test.env with your specific values
   nano test.env
   ```

3. **Run tests:**
   ```bash
   # The test framework will automatically use test.env if it exists
   ./test-model-config-lib.sh
   ```

## Security Notes

- **Never commit real secrets** to version control
- The actual `test.env` file is gitignored to prevent accidental commits
- Use only test tokens and development credentials in test.env
- Template files (`.env.example`) are safe to commit as they contain no real secrets

## Test Framework

The test system creates its own temporary test files:
- `test-basic.env`
- `test-comments.env` 
- `test-mixed.env`
- `test-empty.env`
- `test-malformed.env`

These are created dynamically during test execution and don't need manual configuration.

## Environment Variables

See `test.env.example` for the complete list of configurable test parameters including:
- Ollama host configuration
- Test model selection
- Authentication tokens (test only!)
- Infrastructure host addresses
- Debugging options
