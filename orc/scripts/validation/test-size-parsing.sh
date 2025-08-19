#!/bin/bash
# test-size-parsing.sh - Test the robust size parsing logic

set -euo pipefail

echo "=== TESTING ROBUST SIZE PARSING ==="
echo ""

# Test different ollama list output formats
test_format() {
    local format_name="$1"
    local test_data="$2"
    
    echo "🧪 Testing format: $format_name"
    echo "Input: $test_data"
    
    # Use the same awk logic as the validation script
    result=$(echo "$test_data" | awk '
        {
            # Strategy 1: Look for size pattern (number + unit) with space separation
            size_found = ""
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[0-9]+(\.[0-9]+)?$/ && $(i+1) ~ /^([KMGT]?i?B)$/i) {
                    size_found = $i " " $(i+1)
                    break
                }
            }
            
            # Strategy 2: Look for compact size pattern (number+unit without space)
            if (size_found == "") {
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^[0-9]+(\.[0-9]+)?([KMGT]?i?B)$/i) {
                        # Extract number and unit parts
                        if (match($i, /^([0-9]+(\.[0-9]+)?)([KMGT]?i?B)$/i)) {
                            num_part = substr($i, 1, RSTART + RLENGTH - 1)
                            gsub(/[KMGT]?i?B$/i, "", num_part)
                            unit_part = $i
                            gsub(/^[0-9.]+/, "", unit_part)
                            size_found = num_part " " unit_part
                            break
                        }
                    }
                }
            }
            
            # Strategy 3: Fallback to traditional fields 3-4 if pattern not found
            if (size_found == "" && NF >= 4) {
                # Validate that fields 3-4 look like a size before using them
                if ($3 ~ /^[0-9]+(\.[0-9]+)?$/ && $4 ~ /^([KMGT]?i?B)$/i) {
                    size_found = $3 " " $4
                }
            }
            
            # Strategy 4: Last resort - regex extraction from the entire line
            if (size_found == "") {
                # Match spaced format: "4.2 GB" or "4.2 GiB"
                if (match($0, /[0-9]+(\.[0-9]+)?\s+([KMGT]?i?B)/i)) {
                    size_found = substr($0, RSTART, RLENGTH)
                }
                # Match compact format: "4.2GB" or "4.2GiB"
                else if (match($0, /[0-9]+(\.[0-9]+)?([KMGT]?i?B)/i)) {
                    matched_text = substr($0, RSTART, RLENGTH)
                    # Split into number and unit
                    gsub(/[KMGT]?i?B$/i, "", matched_text)
                    num_part = matched_text
                    unit_part = substr($0, RSTART, RLENGTH)
                    gsub(/^[0-9.]+/, "", unit_part)
                    size_found = num_part " " unit_part
                }
            }
            
            print size_found
        }
    ')
    
    echo "Result: '$result'"
    echo ""
}

# Test various ollama output formats
echo "Testing different ollama list output formats:"
echo "=============================================="

# Standard format (NAME TAG ID SIZE MODIFIED)
test_format "Standard format" "llama3.2:3b abc123 def456 4.2 GB 2024-01-01"

# Alternative format with different field order
test_format "Alternative format" "mistral-small sha256:abc123 15.7 GB modified-yesterday"

# Compact format
test_format "Compact format" "qwen3:1.7b 1.4GB last-week"

# Format with extra fields
test_format "Extended format" "model:latest tag123 id456 extra-field 2.1 MB another-field timestamp"

# Edge case: Size at beginning
test_format "Size at beginning" "3.5 GB model-name tag id timestamp"

# Edge case: No valid size
test_format "No valid size" "model-name tag id timestamp invalid"

# Edge case: Multiple potential sizes
test_format "Multiple sizes" "model 1.0 version 4.2 GB download 500 MB cache"

echo "✅ Size parsing robustness test complete!"
echo ""
echo "💡 The new parsing logic uses multiple strategies:"
echo "   1. Pattern matching for number+unit with space separation"  
echo "   2. Pattern matching for compact number+unit format (no space)"
echo "   3. Validated fallback to fields 3-4"
echo "   4. Regex extraction as last resort (both spaced and compact)"
echo "   This should work across different ollama versions and formats."
