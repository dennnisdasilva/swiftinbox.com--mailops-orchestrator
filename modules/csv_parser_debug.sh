#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/config.sh"

INPUT_FILE="${1:-$PROJECT_ROOT/input/new.csv}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}CSV Parser: Processing $INPUT_FILE${NC}"

if [[ ! -f "$INPUT_FILE" ]]; then
    echo -e "${RED}ERROR: Input file not found: $INPUT_FILE${NC}"
    exit 1
fi

# Check what header we actually have
ACTUAL_HEADER=$(head -n1 "$INPUT_FILE")
echo "DEBUG: Actual header: '$ACTUAL_HEADER'"

EXPECTED_HEADER="action,ip_range,domain1,domain2,domain3,domain4,domain5,domain6,domain7,domain8"
if [[ "$ACTUAL_HEADER" != "$EXPECTED_HEADER" ]]; then
    echo -e "${RED}ERROR: Invalid header${NC}"
    echo "  Expected: $EXPECTED_HEADER"
    echo "  Found: $ACTUAL_HEADER"
    exit 1
fi

echo -e "${GREEN}✓ Header validation passed${NC}"

echo ""
echo "Validating data rows..."
echo "DEBUG: About to start reading loop"

# The issue is likely here - bash read with IFS=',' doesn't handle empty fields well
# Let's process it differently
LINE_NUM=0
VALID_ROWS=0

while IFS= read -r line; do
    ((LINE_NUM++))
    echo "DEBUG: Reading line $LINE_NUM: '$line'"
    
    # Skip header
    if [[ $LINE_NUM -eq 1 ]]; then
        echo "DEBUG: Skipping header"
        continue
    fi
    
    # Skip empty lines
    if [[ -z "$line" ]]; then
        echo "DEBUG: Skipping empty line"
        continue
    fi
    
    # Use a different approach - split the line manually
    IFS=',' read -ra FIELDS <<< "$line"
    
    echo "DEBUG: Found ${#FIELDS[@]} fields"
    
    if [[ ${#FIELDS[@]} -lt 2 ]]; then
        echo "DEBUG: Not enough fields, skipping"
        continue
    fi
    
    action="${FIELDS[0]}"
    ip_range="${FIELDS[1]}"
    
    echo "DEBUG: action='$action', ip_range='$ip_range'"
    
    # Count domains (fields 2-9)
    DOMAIN_COUNT=0
    for i in {2..9}; do
        if [[ $i -lt ${#FIELDS[@]} ]] && [[ -n "${FIELDS[$i]}" ]]; then
            echo "DEBUG: Found domain at position $i: '${FIELDS[$i]}'"
            ((DOMAIN_COUNT++))
        fi
    done
    
    echo "DEBUG: Total domains found: $DOMAIN_COUNT"
    
    # Extract CIDR
    if [[ "$ip_range" =~ /([0-9]+)$ ]]; then
        CIDR="${BASH_REMATCH[1]}"
        echo "DEBUG: CIDR: /$CIDR"
    else
        echo "DEBUG: Could not extract CIDR from '$ip_range'"
        continue
    fi
    
    # Validate
    if [[ "$CIDR" == "24" ]]; then
        if [[ $DOMAIN_COUNT -ne 8 ]]; then
            echo -e "${RED}ERROR: /24 requires exactly 8 domains, found $DOMAIN_COUNT${NC}"
            continue
        fi
        echo -e "${GREEN}✓ Valid /24 with 8 domains${NC}"
    elif [[ "$CIDR" == "27" ]]; then
        if [[ $DOMAIN_COUNT -ne 1 ]]; then
            echo -e "${RED}ERROR: /27 requires exactly 1 domain, found $DOMAIN_COUNT${NC}"
            continue
        fi
        echo -e "${GREEN}✓ Valid /27 with 1 domain${NC}"
    fi
    
    ((VALID_ROWS++))
done < "$INPUT_FILE"

echo ""
echo "DEBUG: Loop completed"
echo "Valid rows: $VALID_ROWS"

if [[ $VALID_ROWS -eq 0 ]]; then
    echo -e "${RED}ERROR: No valid data rows found${NC}"
    exit 1
fi

echo -e "${GREEN}CSV validation successful${NC}"
exit 0
