#!/bin/bash
# inspect-ollama-output.sh - Verification script to inspect 'ollama list' output structure
# This helps validate column assumptions before parsing

set -euo pipefail

echo "=== OLLAMA LIST OUTPUT INSPECTION ==="
echo ""

if ! command -v ollama >/dev/null 2>&1; then
    echo "❌ Ollama not available for inspection"
    exit 1
fi

echo "📊 Capturing 'ollama list' output..."
# Capture ollama list output once for all subsequent analysis
if ! ollama_output=$(ollama list 2>/dev/null); then
    echo "❌ Failed to execute 'ollama list'"
    exit 1
fi

echo "📊 Raw 'ollama list' output:"
echo "----------------------------------------"
echo "$ollama_output"
echo "----------------------------------------"
echo ""

echo "🔍 Field analysis (line by line):"
echo "Format: [Line#] [Field1] [Field2] [Field3] [Field4] [Field5+]"
echo "----------------------------------------"

echo "$ollama_output" | while IFS= read -r line; do
    line_num=$((line_num + 1))
    if [[ -z "$line_num" ]]; then
        line_num=1
    fi
    
    # Parse fields
    read -ra fields <<< "$line"
    
    printf "[%2d] " "$line_num"
    for i in "${!fields[@]}"; do
        printf "[F%d:%s] " "$((i+1))" "${fields[i]}"
    done
    printf "\n"
done
echo "----------------------------------------"
echo ""

echo "📏 Header analysis:"
echo "----------------------------------------"
header_line=$(echo "$ollama_output" | head -n1)
echo "Header: '$header_line'"

# Check if header contains expected columns
if [[ "$header_line" =~ NAME.*TAG.*ID.*SIZE.*MODIFIED ]]; then
    echo "✅ Standard format detected: NAME TAG ID SIZE MODIFIED"
    echo "   SIZE should be in field 4 (may span multiple fields)"
elif [[ "$header_line" =~ NAME.*SIZE ]]; then
    echo "⚠️  Alternative format detected - contains NAME and SIZE"
    echo "   Field positions may vary"
else
    echo "❌ Unexpected format - manual inspection required"
fi
echo "----------------------------------------"
echo ""

echo "🎯 Size field extraction test:"
echo "----------------------------------------"
echo "$ollama_output" | awk 'NR > 1 {
    # Try different extraction strategies
    name = $1
    
    # Strategy 1: Fields 3-4 (current approach)
    size_34 = $3 " " $4
    
    # Strategy 2: Everything after field 2 until MODIFIED timestamp
    size_alt = ""
    for (i = 3; i <= NF-1; i++) {
        if ($i ~ /^[0-9]/) {
            size_alt = $i " " $(i+1)
            break
        }
    }
    
    # Strategy 3: Pattern matching for size-like strings
    size_pattern = ""
    for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9]+(\.[0-9]+)?$/ && $(i+1) ~ /^(B|KB|MB|GB|TB)$/) {
            size_pattern = $i " " $(i+1)
            break
        }
    }
    
    printf "Model: %-20s | F3-F4: %-10s | Alt: %-10s | Pattern: %-10s\n", 
           name, size_34, size_alt, size_pattern
}'
echo "----------------------------------------"
echo ""

echo "💡 RECOMMENDATIONS:"
echo "- Use header-based parsing if format is consistent"
echo "- Implement pattern matching for size fields (number + unit)"
echo "- Consider fallback strategies for different ollama versions"
echo "- Test across different environments and ollama versions"
