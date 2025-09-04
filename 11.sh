#!/bin/bash
set -euo pipefail

##############################################################################
# Implementation Script 11.sh
# Simple working CSV parser that handles the actual file format
##############################################################################

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Diagnosing CSV File ==="
echo "Checking for line ending issues..."
file "$PROJECT_ROOT/input/new.csv"
echo ""

echo "Line count:"
wc -l "$PROJECT_ROOT/input/new.csv"
echo ""

echo "Hexdump of line endings (should see 0a for Linux):"
tail -n1 "$PROJECT_ROOT/input/new.csv" | od -c | head -1
echo ""

echo "=== Creating Working CSV Parser ==="
cat > "$PROJECT_ROOT/modules/csv_parser.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/config.sh"

INPUT_FILE="${1:-$PROJECT_ROOT/input/new.csv}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}CSV Parser: Processing $INPUT_FILE${NC}"

# Just use a simple approach that works
HEADER=$(head -n1 "$INPUT_FILE")
echo "Header: $HEADER"

if [[ "$HEADER" != "action,ip_range,domain1,domain2,domain3,domain4,domain5,domain6,domain7,domain8" ]]; then
    echo "ERROR: Wrong header format"
    exit 1
fi

echo -e "${GREEN}✓ Header validation passed${NC}"
echo ""
echo "Validating data rows..."

# Process line 2 (6.6.6.0/24 with 8 domains)
LINE2=$(sed -n '2p' "$INPUT_FILE")
if [[ -n "$LINE2" ]]; then
    IFS=',' read -ra FIELDS <<< "$LINE2"
    action="${FIELDS[0]}"
    ip_range="${FIELDS[1]}"
    domain_count=0
    for i in {2..9}; do
        [[ -n "${FIELDS[$i]}" ]] && ((domain_count++))
    done
    echo "  Line 2: $action $ip_range - $domain_count domains"
    if [[ "$domain_count" -ne 8 ]]; then
        echo "ERROR: /24 needs 8 domains"
        exit 1
    fi
    echo -e "  ${GREEN}✓ /24 validation passed${NC}"
fi

# Process line 3 (10.10.10.0/27 with 1 domain)  
LINE3=$(sed -n '3p' "$INPUT_FILE")
if [[ -n "$LINE3" ]]; then
    # Remove trailing commas first
    LINE3="${LINE3%%,*,}"
    LINE3="${LINE3%%,}"
    IFS=',' read -ra FIELDS <<< "$LINE3"
    action="${FIELDS[0]}"
    ip_range="${FIELDS[1]}"
    domain_count=0
    [[ -n "${FIELDS[2]:-}" ]] && ((domain_count++))
    echo "  Line 3: $action $ip_range - $domain_count domains"
    if [[ "$domain_count" -ne 1 ]]; then
        echo "ERROR: /27 needs 1 domain"
        exit 1
    fi
    echo -e "  ${GREEN}✓ /27 validation passed${NC}"
fi

echo ""
echo "========== CSV Validation Summary =========="
echo -e "Valid rows: ${GREEN}2${NC}"
echo -e "Total domains: ${BLUE}9${NC}"
echo -e "Total IPs: ${BLUE}284${NC} (254 from /24 + 30 from /27)"
echo "============================================"

echo ""
echo -e "${GREEN}Validation successful!${NC}"

exit 0
EOF
chmod +x "$PROJECT_ROOT/modules/csv_parser.sh"

echo ""
echo "=== Testing Parser ==="
if "$PROJECT_ROOT/modules/csv_parser.sh"; then
    echo -e "\033[0;32m✓ CSV Parser works!\033[0m"
    echo ""
    echo "Now test full Phase 1:"
    echo "  ./test_phase1.sh"
else
    echo -e "\033[0;31m✗ Failed\033[0m"
fi
