#!/bin/bash
# scripts/check-versions.sh
"""
Dependency version checker for HX Gateway
Validates that installed packages match pinned requirements
"""

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}     HX Gateway Dependency Version Check${NC}"
echo -e "${BLUE}===================================================${NC}"
echo ""

cd "$(dirname "$0")/../gateway"

echo -e "${YELLOW}Activating virtual environment...${NC}"
source venv/bin/activate

echo -e "${YELLOW}Checking pinned versions vs installed...${NC}"
echo ""

# Core dependencies to check
CORE_DEPS=("fastapi" "pydantic" "uvicorn" "httpx" "pydantic-settings")

for dep in "${CORE_DEPS[@]}"; do
    echo -n "Checking $dep: "
    
    # Get pinned version from requirements.txt
    if [[ -f "requirements.txt" ]]; then
        PINNED=$(grep "^${dep}" requirements.txt 2>/dev/null | cut -d'~' -f2 | cut -d'=' -f2 || echo "not pinned")
    else
        PINNED="no requirements.txt"
    fi
    
    # Get installed version
    INSTALLED=$(pip show "$dep" 2>/dev/null | grep "Version:" | cut -d' ' -f2 || echo "not installed")
    
    if [[ "$INSTALLED" == "not installed" ]]; then
        echo -e "${RED}❌ Not installed${NC}"
    elif [[ "$PINNED" == "not pinned" ]] || [[ "$PINNED" == "no requirements.txt" ]]; then
        echo -e "${YELLOW}⚠️  Installed: $INSTALLED (no pin)${NC}"
    else
        # Simple compatibility check (major.minor)
        PINNED_MAJOR_MINOR=$(echo "$PINNED" | cut -d'.' -f1,2)
        INSTALLED_MAJOR_MINOR=$(echo "$INSTALLED" | cut -d'.' -f1,2)
        
        if [[ "$PINNED_MAJOR_MINOR" == "$INSTALLED_MAJOR_MINOR" ]]; then
            echo -e "${GREEN}✅ $INSTALLED (compatible with ~=$PINNED)${NC}"
        else
            echo -e "${RED}❌ $INSTALLED (expected ~=$PINNED)${NC}"
        fi
    fi
done

echo ""
echo -e "${YELLOW}Full installed versions:${NC}"
pip list | grep -E "(fastapi|pydantic|uvicorn|httpx|pytest)" | sort

echo ""
echo -e "${YELLOW}Requirements files:${NC}"
if [[ -f "requirements.txt" ]]; then
    echo -e "${GREEN}✅ requirements.txt found${NC}"
    echo "   Core pins:"
    grep -E "(fastapi|pydantic|uvicorn|httpx)" requirements.txt | sed 's/^/     /'
else
    echo -e "${YELLOW}⚠️  No requirements.txt found${NC}"
fi

if [[ -f "requirements.lock" ]]; then
    echo -e "${GREEN}✅ requirements.lock found${NC}"
else
    echo -e "${YELLOW}⚠️  No requirements.lock found${NC}"
fi

echo ""
echo -e "${BLUE}Recommendation:${NC}"
echo "Keep requirements.txt for development with pinned versions (~=)"
echo "Use requirements.lock for production with exact versions (==)"
echo ""
echo -e "${GREEN}Version check complete!${NC}"
