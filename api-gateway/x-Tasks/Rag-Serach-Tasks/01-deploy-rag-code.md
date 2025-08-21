# Engineering Task: Deploy RAG Feature Code and Dependencies

> **Task ID**: `RAG-001`  
> **Priority**: `High`  
> **Assigned To**: `[Team Member]`  
> **Due Date**: `[YYYY-MM-DD]`

---

## 🎯 Objective
To deploy the new Python source code for the RAG search feature and ensure all required package dependencies are installed in the correct virtual environment.

---

## ✅ Execution Plan

### Step 0: Verify Preconditions
*Ensure the target server is accessible and you have `sudo` privileges.*

1.  **Deploy RAG Source Code**
    - In a real-world scenario, this would be a `git pull` from the repository. For this task, we will confirm the presence of the key files that should be deployed via the CI/CD pipeline.
2.  **Install Dependencies**
    - Ensure the `httpx` dependency is installed in the service's virtual environment.
    ```bash
    VENV="/opt/HX-Infrastructure-/api-gateway/gateway/venv"
    echo "Ensuring httpx dependency is installed..."
    sudo $VENV/bin/pip install -q "httpx>=0.27"
    ```

---

## 🧪 Validation Criteria

### Test Case
- **Description**: Verify that the RAG route's source file is present and that the `httpx` dependency can be imported by the service's Python interpreter.
- **Expected Result**: Both validation checks print a success message.

### Test Steps
1.  **Verify RAG route file:**
    ```bash
    if [ -f "/opt/HX-Infrastructure-/api-gateway/gateway/src/routes/rag.py" ]; then
        echo "✅ Code Validation: RAG route file is present."
    else
        echo "❌ Code Validation: RAG route file is missing."
        exit 1
    fi
    ```
2.  **Verify dependency installation:**
    ```bash
    VENV="/opt/HX-Infrastructure-/api-gateway/gateway/venv"
    $VENV/bin/python -c "import httpx; print('✅ Dependency Validation: httpx is installed.')"
    ```

---

## 📊 Status Tracking

- **Current Status**: `Not Started`
- **Completion**: `0%`
- **Last Updated**: `2025-08-21`

### Change Log
- **2025-08-21**: Task created from `rag-search-overview.md`.

---

## 📎 Additional Information

### Notes
- This task is the first step in enabling the RAG search endpoint.
