#!/bin/bash
# scripts/tests/check-openapi.sh
#
# Comprehensive OpenAPI validation - ensures schema is valid, complete, and consistent.
# Part of Step 7: CI gates to prevent architectural drift and regression.

set -Eeuo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BASE_URL="${GATEWAY_BASE:-http://127.0.0.1:4010}"
OPENAPI_URL="${BASE_URL}/openapi.json"
MIN_PATHS=5  # Minimum number of paths expected

echo -e "${YELLOW}🔍 Checking OpenAPI schema at: ${OPENAPI_URL}${NC}"

# Test that OpenAPI endpoint is accessible and returns valid JSON
echo -e "${YELLOW}📡 Fetching OpenAPI schema...${NC}"
if ! response=$(curl -fsS "${OPENAPI_URL}" 2>/dev/null); then
    echo -e "${RED}❌ Failed to fetch OpenAPI schema from ${OPENAPI_URL}${NC}"
    echo "   Make sure the API Gateway is running on ${BASE_URL}"
    exit 1
fi

# Validate JSON structure
echo -e "${YELLOW}🔍 Validating JSON structure...${NC}"
if ! echo "${response}" | jq . >/dev/null 2>&1; then
    echo -e "${RED}❌ OpenAPI response is not valid JSON${NC}"
    exit 1
fi

# Check that paths exist and meet minimum count
echo -e "${YELLOW}📊 Analyzing OpenAPI paths...${NC}"
paths_count=$(echo "${response}" | jq -er '.paths | length' 2>/dev/null || echo "0")

if [[ "${paths_count}" -lt "${MIN_PATHS}" ]]; then
    echo -e "${RED}❌ OpenAPI schema has too few paths: ${paths_count} (minimum: ${MIN_PATHS})${NC}"
    echo "   This may indicate annotation/schema generation issues"
    exit 1
fi

# Check for required endpoints
echo -e "${YELLOW}🎯 Checking for required endpoints...${NC}"
required_paths=("/healthz" "/v1/rag/upsert" "/v1/rag/search")
missing_paths=()

for path in "${required_paths[@]}"; do
    if ! echo "${response}" | jq -e ".paths[\"${path}\"]" >/dev/null 2>&1; then
        missing_paths+=("${path}")
    fi
done

if [[ ${#missing_paths[@]} -gt 0 ]]; then
    echo -e "${RED}❌ Missing required paths in OpenAPI schema:${NC}"
    printf "   - %s\n" "${missing_paths[@]}"
    exit 1
fi

# Check for valid operation IDs (no duplicates or generation issues)
echo -e "${YELLOW}🔍 Checking operation IDs...${NC}"
operation_ids=$(echo "${response}" | jq -r '
    .paths 
    | to_entries[] 
    | .value 
    | to_entries[] 
    | .value.operationId // empty
' | sort)

duplicate_count=$(echo "${operation_ids}" | uniq -d | wc -l)
if [[ "${duplicate_count}" -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Found duplicate operation IDs:${NC}"
    echo "${operation_ids}" | uniq -d | sed 's/^/   - /'
    echo "   This may cause OpenAPI client generation issues"
    # Don't fail on duplicates, just warn
fi

# Check for model schemas
echo -e "${YELLOW}📝 Checking model schemas...${NC}"
if echo "${response}" | jq -e 'has("components") and .components | has("schemas")' >/dev/null 2>&1; then
    model_count=$(echo "${response}" | jq -r '.components.schemas | length')
    echo -e "${GREEN}✅ Found ${model_count} model schemas${NC}"
else
    echo -e "${YELLOW}⚠️  No component schemas found (models might be inlined)${NC}"
fi

# Check that responses have proper content types
echo -e "${YELLOW}📋 Checking response formats...${NC}"
json_responses=$(echo "${response}" | jq -r '
    .paths 
    | to_entries[] 
    | .value 
    | to_entries[] 
    | .value.responses 
    | to_entries[] 
    | .value 
    | select(has("content")) 
    | .content 
    | has("application/json")
' | grep -c true || echo "0")

if [[ "${json_responses}" -gt 0 ]]; then
    echo -e "${GREEN}✅ Found ${json_responses} JSON response definitions${NC}"
else
    echo -e "${YELLOW}⚠️  No explicit JSON response definitions found${NC}"
fi

# Test health endpoint works
echo -e "${YELLOW}🧪 Testing endpoint responses...${NC}"
if curl -fsS "${BASE_URL}/healthz" | jq -e '.ok == true' >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Health endpoint responds correctly${NC}"
else
    echo -e "${RED}❌ Health endpoint failed${NC}"
    exit 1
fi

# Test that unauthorized requests return 401 (not 500)
echo -e "${YELLOW}🔒 Testing authentication...${NC}"
auth_response_code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/v1/rag/upsert" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"documents":[{"text":"test","namespace":"test"}]}')

if [[ "${auth_response_code}" = "401" ]]; then
    echo -e "${GREEN}✅ Unauthorized requests return 401${NC}"
else
    echo -e "${RED}❌ Unauthorized requests return ${auth_response_code} (expected 401)${NC}"
    exit 1
fi

# Success
echo
echo -e "${GREEN}🎉 OpenAPI schema validation passed!${NC}"
echo -e "${GREEN}   📈 Total paths: ${paths_count}${NC}"
echo -e "${GREEN}   🎯 Required endpoints: ✓ all present${NC}"
echo -e "${GREEN}   🔧 JSON structure: ✓ valid${NC}"
echo -e "${GREEN}   🔒 Authentication: ✓ working${NC}"

exit 0
