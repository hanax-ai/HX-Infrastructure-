#!/bin/bash
# test-model-config-lib.sh - Unit tests for the shared model-config.sh library

set -euo pipefail

# Source the library under test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/model-config.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0

# Test helper functions
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo "🧪 Running test: $test_name"
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if $test_function; then
        echo "  ✅ PASSED"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  ❌ FAILED"
    fi
    echo ""
}

# Create test environment files
setup_test_files() {
    # Basic test file
    cat > test-basic.env << 'EOF'
OLLAMA_MODEL_LLAMA="llama3.2:3b"
OLLAMA_MODEL_QWEN='qwen2.5:7b'
OLLAMA_MODEL_UNQUOTED=mistral:latest

OLLAMA_MODELS_AVAILABLE="llama3.2:3b,qwen2.5:7b,mistral:latest"
OLLAMA_HOST="0.0.0.0:11434"
EOF

    # Test file with comments and edge cases
    cat > test-comments.env << 'EOF'
OLLAMA_MODEL_QUOTED="model:tag" # External comment
OLLAMA_MODEL_HASH_INSIDE="model#hash:tag" # Hash inside quotes
  OLLAMA_MODEL_INDENTED=unquoted_value # Indented variable
OLLAMA_MODEL_mixed_Case="mixed:case" # Mixed case name

OLLAMA_MODELS_AVAILABLE="model:tag,model#hash:tag,unquoted_value" # Available list with comment
EOF

    # Test file with mixed case and spaces
    cat > test-mixed.env << 'EOF'
OLLAMA_MODEL_UPPER="upper:model"
OLLAMA_MODEL_lower_case="lower:model"
  OLLAMA_MODEL_Mixed_Case="mixed:model"
OLLAMA_MODEL_with_NUMBERS_123="numbers:model"

OLLAMA_MODELS_AVAILABLE=" upper:model , lower:model, mixed:model ,numbers:model "
EOF

    # Empty/invalid test file
    cat > test-empty.env << 'EOF'
# No model variables here
OLLAMA_MODELS_AVAILABLE=""
OTHER_VAR="not a model"
EOF

    # Malformed file for error testing
    cat > test-malformed.env << 'EOF'
OLLAMA_MODEL_MISSING_EQUALS
OLLAMA_MODEL_INCOMPLETE=
OLLAMA_MODELS_EXCLUDED="should be excluded"
EOF
}

cleanup_test_files() {
    rm -f test-*.env
}

# Test: extract_model_references with basic file
test_basic_extraction() {
    local output=$(extract_model_references "test-basic.env" 2>/dev/null)
    
    # Check if all expected models are found
    if [[ "$output" == *"OLLAMA_MODEL_LLAMA = llama3.2:3b"* ]] && \
       [[ "$output" == *"OLLAMA_MODEL_QWEN = qwen2.5:7b"* ]] && \
       [[ "$output" == *"OLLAMA_MODEL_UNQUOTED = mistral:latest"* ]] && \
       [[ "$output" == *"Available models list: llama3.2:3b,qwen2.5:7b,mistral:latest"* ]]; then
        return 0
    else
        echo "Expected basic model extraction failed"
        echo "Output: $output"
        return 1
    fi
}

# Test: extract_model_references with comments
test_comment_handling() {
    local output=$(extract_model_references "test-comments.env" 2>/dev/null)
    
    # Check that comments are properly handled
    if [[ "$output" == *"OLLAMA_MODEL_QUOTED = model:tag"* ]] && \
       [[ "$output" == *"OLLAMA_MODEL_HASH_INSIDE = model#hash:tag"* ]] && \
       [[ "$output" == *"OLLAMA_MODEL_INDENTED = unquoted_value"* ]] && \
       [[ "$output" == *"OLLAMA_MODEL_mixed_Case = mixed:case"* ]]; then
        return 0
    else
        echo "Comment handling test failed"
        echo "Output: $output"
        return 1
    fi
}

# Test: extract_model_references with mixed case
test_mixed_case() {
    local output=$(extract_model_references "test-mixed.env" 2>/dev/null)
    
    # Check that mixed case variables are detected
    if [[ "$output" == *"OLLAMA_MODEL_UPPER = upper:model"* ]] && \
       [[ "$output" == *"OLLAMA_MODEL_lower_case = lower:model"* ]] && \
       [[ "$output" == *"OLLAMA_MODEL_Mixed_Case = mixed:model"* ]] && \
       [[ "$output" == *"OLLAMA_MODEL_with_NUMBERS_123 = numbers:model"* ]]; then
        return 0
    else
        echo "Mixed case test failed"
        echo "Output: $output"
        return 1
    fi
}

# Test: extract_model_value helper function
test_extract_model_value() {
    local test_line='OLLAMA_MODEL_TEST="quoted value" # comment'
    local result=$(extract_model_value "$test_line")
    
    if [[ "$result" == "quoted value" ]]; then
        return 0
    else
        echo "extract_model_value test failed. Expected 'quoted value', got '$result'"
        return 1
    fi
}

# Test: is_model_variable helper function
test_is_model_variable() {
    local valid_line='OLLAMA_MODEL_TEST="value"'
    local invalid_line='OLLAMA_MODELS_AVAILABLE="list"'
    local other_line='OTHER_VAR="value"'
    
    if is_model_variable "$valid_line" && \
       ! is_model_variable "$invalid_line" && \
       ! is_model_variable "$other_line"; then
        return 0
    else
        echo "is_model_variable test failed"
        return 1
    fi
}

# Test: Error handling for missing file
test_error_handling() {
    local output=$(extract_model_references "nonexistent.env" 2>&1)
    
    if [[ "$output" == *"does not exist or is not readable"* ]]; then
        return 0
    else
        echo "Error handling test failed. Output: $output"
        return 1
    fi
}

# Test: Empty file handling
test_empty_file() {
    local output=$(extract_model_references "test-empty.env" 2>/dev/null)
    
    # Should show no individual variables but still show the empty available list
    if [[ "$output" == *"Individual model variables:"* ]] && \
       [[ "$output" == *"Available models list:"* ]] && \
       [[ "$output" != *"OLLAMA_MODEL_"* ]]; then
        return 0
    else
        echo "Empty file test failed"
        echo "Output: $output"
        return 1
    fi
}

# Main test execution
main() {
    echo "🚀 Starting model-config.sh library tests"
    echo ""
    
    # Setup test environment
    setup_test_files
    
    # Run all tests
    run_test "Basic model extraction" test_basic_extraction
    run_test "Comment handling" test_comment_handling
    run_test "Mixed case support" test_mixed_case
    run_test "extract_model_value helper" test_extract_model_value
    run_test "is_model_variable helper" test_is_model_variable
    run_test "Error handling" test_error_handling
    run_test "Empty file handling" test_empty_file
    
    # Cleanup
    cleanup_test_files
    
    # Report results
    echo "📊 Test Results:"
    echo "  Tests run: $TESTS_RUN"
    echo "  Tests passed: $TESTS_PASSED"
    echo "  Tests failed: $((TESTS_RUN - TESTS_PASSED))"
    
    if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
        echo ""
        echo "🎉 All tests passed!"
        exit 0
    else
        echo ""
        echo "❌ Some tests failed!"
        exit 1
    fi
}

# Run the tests
main "$@"
