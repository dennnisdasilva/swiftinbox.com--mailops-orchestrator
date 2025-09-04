#!/bin/bash
set -euo pipefail

##############################################################################
# Implementation Script 10.sh
# Diagnose why csv_parser.sh is failing silently and fix it
##############################################################################

echo "=============================================="
echo "CSV Parser Diagnostic and Fix"
echo "Script 10.sh"
echo "=============================================="
echo ""

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# First, let's see what's actually happening
echo "=== Debugging Current CSV Parser ==="
echo "Adding debug output to see where it's failing..."
echo ""

# Create a diagnostic version that shows us what's happening
cat > "$PROJECT_ROOT/modules/csv_parser_debug.sh" << 'EOF'
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
EOF

chmod +x "$PROJECT_ROOT/modules/csv_parser_debug.sh"

echo "Running diagnostic version..."
echo "-------------------------------------------"
"$PROJECT_ROOT/modules/csv_parser_debug.sh" || true
echo "-------------------------------------------"
echo ""

# Now create the fixed version without all the debug output
echo "=== Creating Fixed CSV Parser ==="
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
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}CSV Parser: Processing $INPUT_FILE${NC}"

if [[ ! -f "$INPUT_FILE" ]]; then
    echo -e "${RED}ERROR: Input file not found: $INPUT_FILE${NC}"
    exit 1
fi

# Validate header
ACTUAL_HEADER=$(head -n1 "$INPUT_FILE")
EXPECTED_HEADER="action,ip_range,domain1,domain2,domain3,domain4,domain5,domain6,domain7,domain8"

if [[ "$ACTUAL_HEADER" != "$EXPECTED_HEADER" ]]; then
    echo -e "${RED}ERROR: Invalid header${NC}"
    echo "  Expected: $EXPECTED_HEADER"
    echo "  Found: $ACTUAL_HEADER"
    exit 1
fi

echo -e "${GREEN}✓ Header validation passed${NC}"

# Process data rows
LINE_NUM=0
VALID_ROWS=0
ADD_ROWS=0
TOTAL_DOMAINS=0
TOTAL_IPS_24=0
TOTAL_IPS_27=0

echo ""
echo "Validating data rows..."

while IFS= read -r line; do
    ((LINE_NUM++))
    
    # Skip header
    [[ $LINE_NUM -eq 1 ]] && continue
    
    # Skip empty lines
    [[ -z "$line" ]] && continue
    
    # Parse fields
    IFS=',' read -ra FIELDS <<< "$line"
    
    [[ ${#FIELDS[@]} -lt 2 ]] && continue
    
    action="${FIELDS[0]}"
    ip_range="${FIELDS[1]}"
    
    # Count non-empty domains
    DOMAIN_COUNT=0
    for i in {2..9}; do
        if [[ $i -lt ${#FIELDS[@]} ]] && [[ -n "${FIELDS[$i]}" ]]; then
            ((DOMAIN_COUNT++))
        fi
    done
    
    echo "  Line $LINE_NUM: action='$action', ip='$ip_range', domains=$DOMAIN_COUNT"
    
    # Extract CIDR
    if [[ "$ip_range" =~ /([0-9]+)$ ]]; then
        CIDR="${BASH_REMATCH[1]}"
    else
        echo -e "${RED}    ERROR: Invalid IP range format: $ip_range${NC}"
        continue
    fi
    
    # Validate action
    if [[ "$action" != "add" && "$action" != "remove" && "$action" != "update" ]]; then
        echo -e "${RED}    ERROR: Invalid action: $action${NC}"
        continue
    fi
    
    # Validate domain count for CIDR
    if [[ "$CIDR" == "24" ]]; then
        if [[ $DOMAIN_COUNT -ne 8 ]]; then
            echo -e "${RED}    ERROR: /24 requires exactly 8 domains, found $DOMAIN_COUNT${NC}"
            continue
        fi
        TOTAL_IPS_24=$((TOTAL_IPS_24 + 254))
        echo -e "    ${GREEN}✓${NC} /24 validation passed"
    elif [[ "$CIDR" == "27" ]]; then
        if [[ $DOMAIN_COUNT -ne 1 ]]; then
            echo -e "${RED}    ERROR: /27 requires exactly 1 domain, found $DOMAIN_COUNT${NC}"
            continue
        fi
        TOTAL_IPS_27=$((TOTAL_IPS_27 + 30))
        echo -e "    ${GREEN}✓${NC} /27 validation passed"
    else
        echo -e "${YELLOW}    WARNING: Non-standard CIDR /$CIDR${NC}"
    fi
    
    # Count statistics
    [[ "$action" == "add" ]] && ((ADD_ROWS++))
    ((VALID_ROWS++))
    TOTAL_DOMAINS=$((TOTAL_DOMAINS + DOMAIN_COUNT))
    
    echo -e "  ${GREEN}✓ Line $LINE_NUM valid${NC}"
    
done < "$INPUT_FILE"

# Check results
if [[ $VALID_ROWS -eq 0 ]]; then
    echo -e "${RED}ERROR: No valid data rows found${NC}"
    exit 1
fi

# Summary
echo ""
echo "========== CSV Validation Summary =========="
echo -e "Valid rows: ${GREEN}$VALID_ROWS${NC}"
echo -e "  Add actions: ${GREEN}$ADD_ROWS${NC}"
echo -e "Total domains: ${BLUE}$TOTAL_DOMAINS${NC}"
echo -e "Total IPs to allocate:"
echo -e "  From /24 blocks: ${BLUE}$TOTAL_IPS_24${NC}"
echo -e "  From /27 blocks: ${BLUE}$TOTAL_IPS_27${NC}"
echo -e "  Total: ${BLUE}$((TOTAL_IPS_24 + TOTAL_IPS_27))${NC}"
echo "============================================"

# Save report
REPORT_DIR="$PROJECT_ROOT/reports"
mkdir -p "$REPORT_DIR"
REPORT_FILE="$REPORT_DIR/csv_validation_$(date +%Y%m%d_%H%M%S).txt"

{
    echo "CSV Validation Report"
    echo "Date: $(date)"
    echo "Input file: $INPUT_FILE"
    echo ""
    echo "Statistics:"
    echo "  Valid rows: $VALID_ROWS"
    echo "  Add actions: $ADD_ROWS"
    echo "  Total domains: $TOTAL_DOMAINS"
    echo "  Total IPs: $((TOTAL_IPS_24 + TOTAL_IPS_27))"
} > "$REPORT_FILE"

echo ""
echo -e "${GREEN}Validation successful!${NC}"
echo "Report saved to: $REPORT_FILE"

exit 0
EOF

chmod +x "$PROJECT_ROOT/modules/csv_parser.sh"

echo ""
echo "=== Testing Fixed Version ==="
if "$PROJECT_ROOT/modules/csv_parser.sh"; then
    echo ""
    echo -e "\033[0;32m✓ CSV Parser is now working\033[0m"
    echo ""
    echo "Run: ./test_phase1.sh"
else
    echo ""
    echo -e "\033[0;31m✗ Still failing - check output above\033[0m"
fi
