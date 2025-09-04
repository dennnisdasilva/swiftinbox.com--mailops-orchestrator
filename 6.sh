#!/bin/bash
set -euo pipefail

##############################################################################
# Implementation Script 6.sh
# Diagnostic version that shows errors and fixes empty field parsing
##############################################################################

echo "=============================================="
echo "MailOps Orchestrator - CSV Parser Diagnostic Fix"
echo "Implementation Script 6.sh"
echo "=============================================="
echo ""

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# First, let's see what's actually in the CSV
echo "=== Current CSV Contents ==="
echo "File: input/new.csv"
echo "----------------------------"
cat "$PROJECT_ROOT/input/new.csv"
echo "----------------------------"
echo ""

# Test what the current parser sees
echo "=== Testing Current Parser ==="
echo "Let's see what the parser is actually reading..."
echo ""

# Simple diagnostic read
echo "Raw field parsing test:"
LINE_NUM=0
while IFS=',' read -r f1 f2 f3 f4 f5 f6 f7 f8 f9 f10; do
    ((LINE_NUM++))
    echo "Line $LINE_NUM:"
    echo "  Field 1 (action): '$f1'"
    echo "  Field 2 (ip_range): '$f2'"
    echo "  Field 3 (domain1): '$f3'"
    echo "  Field 4 (domain2): '$f4'"
    echo "  Field 10 (domain8): '$f10'"
    if [[ $LINE_NUM -ge 3 ]]; then
        break
    fi
done < "$PROJECT_ROOT/input/new.csv"

echo ""
echo "The problem: IFS=',' with read doesn't handle trailing empty fields correctly!"
echo ""

##############################################################################
# Create Fixed CSV Parser
##############################################################################
echo "=== Creating Fixed CSV Parser ==="
cat > "$PROJECT_ROOT/modules/csv_parser.sh" << 'MODULE_EOF'
#!/bin/bash
set -euo pipefail

##############################################################################
# CSV Parser Module - Fixed for empty fields
# Properly handles trailing empty fields in fixed column format
##############################################################################

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

# Check file exists
if [[ ! -f "$INPUT_FILE" ]]; then
    echo -e "${RED}ERROR: Input file not found: $INPUT_FILE${NC}"
    exit 1
fi

# Validate header
EXPECTED_HEADER="action,ip_range,domain1,domain2,domain3,domain4,domain5,domain6,domain7,domain8"
ACTUAL_HEADER=$(head -n1 "$INPUT_FILE")

if [[ "$ACTUAL_HEADER" != "$EXPECTED_HEADER" ]]; then
    echo -e "${RED}ERROR: Invalid header${NC}"
    echo "  Expected: $EXPECTED_HEADER"
    echo "  Found: $ACTUAL_HEADER"
    exit 1
fi

echo -e "${GREEN}✓ Header validation passed${NC}"

# Process each row using a different approach for empty fields
LINE_NUM=0
VALID_ROWS=0
ADD_ROWS=0
REMOVE_ROWS=0
TOTAL_DOMAINS=0
TOTAL_IPS_24=0
TOTAL_IPS_27=0

echo ""
echo "Validating data rows..."

while IFS= read -r line; do
    ((LINE_NUM++))
    
    # Skip header
    if [[ $LINE_NUM -eq 1 ]]; then
        continue
    fi
    
    # Skip completely empty lines
    if [[ -z "$line" ]]; then
        continue
    fi
    
    # Parse fields using array to handle empty fields correctly
    IFS=',' read -ra FIELDS <<< "$line"
    
    # Ensure we have at least 2 fields (action and ip_range)
    if [[ ${#FIELDS[@]} -lt 2 ]]; then
        echo -e "${RED}  Line $LINE_NUM: Invalid format - not enough fields${NC}"
        continue
    fi
    
    action="${FIELDS[0]:-}"
    ip_range="${FIELDS[1]:-}"
    
    # Collect domains (fields 2-9, indices 2-9)
    domains=()
    for i in {2..9}; do
        if [[ $i -lt ${#FIELDS[@]} ]] && [[ -n "${FIELDS[$i]}" ]]; then
            domains+=("${FIELDS[$i]}")
        fi
    done
    
    DOMAIN_COUNT=${#domains[@]}
    
    echo -e "  Line $LINE_NUM: action='$action', ip='$ip_range', domains=$DOMAIN_COUNT"
    
    # Show domains found
    if [[ $DOMAIN_COUNT -gt 0 ]]; then
        for domain in "${domains[@]}"; do
            echo -e "    - $domain"
        done
    fi
    
    # Extract CIDR mask
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
    
    # Count valid rows by action
    if [[ "$action" == "add" ]]; then
        ((ADD_ROWS++))
    elif [[ "$action" == "remove" ]]; then
        ((REMOVE_ROWS++))
    fi
    
    ((VALID_ROWS++))
    TOTAL_DOMAINS=$((TOTAL_DOMAINS + DOMAIN_COUNT))
    
    echo -e "  ${GREEN}✓ Line $LINE_NUM valid${NC}"
    
done < "$INPUT_FILE"

# Check if we found any valid rows
if [[ $VALID_ROWS -eq 0 ]]; then
    echo -e "${RED}ERROR: No valid data rows found${NC}"
    exit 1
fi

# Summary
echo ""
echo "========== CSV Validation Summary =========="
echo -e "Total lines processed: $((LINE_NUM - 1))"
echo -e "Valid rows: ${GREEN}$VALID_ROWS${NC}"
echo -e "  Add actions: ${GREEN}$ADD_ROWS${NC}"
echo -e "  Remove actions: ${YELLOW}$REMOVE_ROWS${NC}"
echo -e "Total domains: ${BLUE}$TOTAL_DOMAINS${NC}"
echo -e "Total IPs to allocate:"
echo -e "  From /24 blocks: ${BLUE}$TOTAL_IPS_24${NC}"
echo -e "  From /27 blocks: ${BLUE}$TOTAL_IPS_27${NC}"
echo -e "  Total: ${BLUE}$((TOTAL_IPS_24 + TOTAL_IPS_27))${NC}"
echo "============================================"

# Write validation report
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
    echo "  Remove actions: $REMOVE_ROWS"
    echo "  Total domains: $TOTAL_DOMAINS"
    echo "  Total IPs: $((TOTAL_IPS_24 + TOTAL_IPS_27))"
} > "$REPORT_FILE"

echo ""
echo -e "${GREEN}Validation successful!${NC}"
echo "Report saved to: $REPORT_FILE"

# Show the report contents
echo ""
echo "=== Report Contents ==="
cat "$REPORT_FILE"
echo "======================="

exit 0
MODULE_EOF
chmod +x "$PROJECT_ROOT/modules/csv_parser.sh"
echo "  Fixed: modules/csv_parser.sh"

##############################################################################
# Test the fix
##############################################################################
echo ""
echo "=== Testing Fixed Parser ==="
if "$PROJECT_ROOT/modules/csv_parser.sh" 2>&1 | tee "$PROJECT_ROOT/logs/csv_parser_test.log"; then
    echo ""
    echo -e "\033[0;32m✓ CSV Parser now works!\033[0m"
    SUCCESS=true
else
    echo ""
    echo -e "\033[0;31m✗ CSV Parser still failing\033[0m"
    SUCCESS=false
fi

# Show log file
echo ""
echo "=== Log Output ==="
echo "Log saved to: logs/csv_parser_test.log"
if [[ -f "$PROJECT_ROOT/logs/csv_parser_test.log" ]]; then
    echo "Last 20 lines of log:"
    echo "----------------------------"
    tail -20 "$PROJECT_ROOT/logs/csv_parser_test.log"
    echo "----------------------------"
fi

# Show any error reports
if [[ -d "$PROJECT_ROOT/reports" ]]; then
    echo ""
    echo "=== Recent Reports ==="
    ls -lt "$PROJECT_ROOT/reports/" | head -5
fi

echo ""
echo "=============================================="
echo "Script 6.sh Complete!"
echo "=============================================="
echo ""

if $SUCCESS; then
    echo "The CSV parser is now working correctly!"
    echo ""
    echo "Next: Run the full Phase 1 test:"
    echo "  ./test_phase1.sh"
else
    echo "Parser still has issues. Check the log output above."
    echo ""
    echo "To see full debug output:"
    echo "  cat logs/csv_parser_test.log"
fi
echo ""
