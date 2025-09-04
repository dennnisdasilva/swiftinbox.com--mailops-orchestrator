#!/bin/bash
set -euo pipefail

##############################################################################
# Implementation Script 4.sh
# Fixes CSV parser to handle quoted fields with embedded commas
##############################################################################

echo "=============================================="
echo "MailOps Orchestrator - CSV Parser Fix"
echo "Implementation Script 4.sh"
echo "=============================================="
echo ""

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Backup existing parser
if [[ -f "$PROJECT_ROOT/modules/csv_parser.sh" ]]; then
    echo "Backing up existing csv_parser.sh..."
    cp "$PROJECT_ROOT/modules/csv_parser.sh" "$PROJECT_ROOT/modules/csv_parser.sh.backup"
fi

##############################################################################
# Fixed CSV Parser
##############################################################################
echo "=== Creating Fixed CSV Parser ==="
cat > "$PROJECT_ROOT/modules/csv_parser.sh" << 'MODULE_EOF'
#!/bin/bash
set -euo pipefail

##############################################################################
# CSV Parser Module - Fixed for quoted fields
# Properly handles: add,6.6.6.0/24,"domain1.net,domain2.net,..."
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
EXPECTED_HEADER="action,ip_range,domains"
ACTUAL_HEADER=$(head -n1 "$INPUT_FILE")

if [[ "$ACTUAL_HEADER" != "$EXPECTED_HEADER" ]]; then
    echo -e "${RED}ERROR: Invalid header${NC}"
    echo "  Expected: $EXPECTED_HEADER"
    echo "  Found: $ACTUAL_HEADER"
    exit 1
fi

echo -e "${GREEN}✓ Header validation passed${NC}"

# Process each row using proper CSV parsing
LINE_NUM=0
VALID_ROWS=0
ADD_ROWS=0
REMOVE_ROWS=0
TOTAL_DOMAINS=0
TOTAL_IPS_24=0
TOTAL_IPS_27=0

echo ""
echo "Validating data rows..."

# Use a different approach for parsing CSV with quoted fields
while IFS= read -r line; do
    ((LINE_NUM++))
    
    # Skip header
    if [[ $LINE_NUM -eq 1 ]]; then
        continue
    fi
    
    # Skip empty lines
    if [[ -z "$line" ]]; then
        continue
    fi
    
    # Parse CSV line properly handling quoted fields
    # Extract action (first field)
    action=$(echo "$line" | cut -d',' -f1)
    
    # Extract ip_range (second field)
    ip_range=$(echo "$line" | cut -d',' -f2)
    
    # Extract domains (everything after second comma, removing quotes)
    domains_raw=$(echo "$line" | cut -d',' -f3-)
    # Remove surrounding quotes
    domains="${domains_raw%\"}"
    domains="${domains#\"}"
    
    # Debug output
    echo -e "  Line $LINE_NUM: action='$action', ip='$ip_range'"
    
    # Count domains
    DOMAIN_COUNT=$(echo "$domains" | tr ',' '\n' | grep -v '^$' | wc -l)
    echo -e "    Found $DOMAIN_COUNT domains"
    
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
            echo -e "    Domains: $domains"
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
        echo -e "${YELLOW}    WARNING: Unsupported CIDR /$CIDR${NC}"
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

exit 0
MODULE_EOF
chmod +x "$PROJECT_ROOT/modules/csv_parser.sh"
echo "  Fixed: modules/csv_parser.sh"

##############################################################################
# Quick test of the fix
##############################################################################
echo ""
echo "=== Testing the fix with your new.csv ==="
echo ""

if [[ -f "$PROJECT_ROOT/input/new.csv" ]]; then
    echo "Your new.csv contents:"
    echo "----------------------"
    cat "$PROJECT_ROOT/input/new.csv"
    echo "----------------------"
    echo ""
    echo "Running fixed CSV parser..."
    echo ""
    
    if "$PROJECT_ROOT/modules/csv_parser.sh"; then
        echo ""
        echo -e "\033[0;32m✓ CSV parser is now working!\033[0m"
        echo ""
        echo "You can now run the full Phase 1 test:"
        echo "  ./test_phase1.sh"
    else
        echo ""
        echo -e "\033[0;31mParser still has issues - please share the error output\033[0m"
    fi
else
    echo "No input/new.csv found to test"
fi

echo ""
echo "=============================================="
echo "Script 4.sh Complete!"
echo "=============================================="
