#!/bin/bash
set -euo pipefail

##############################################################################
# Implementation Script 5.sh
# Updates everything to use fixed column format (domain1-domain8)
# No quotes, simple parsing, clear validation
##############################################################################

echo "=============================================="
echo "MailOps Orchestrator - Fixed Column Format"
echo "Implementation Script 5.sh"
echo "=============================================="
echo ""

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

##############################################################################
# Create new sample new.csv with fixed columns
##############################################################################
echo "=== Creating new.csv with fixed column format ==="
cat > "$PROJECT_ROOT/input/new.csv" << 'CSV_EOF'
action,ip_range,domain1,domain2,domain3,domain4,domain5,domain6,domain7,domain8
add,6.6.6.0/24,domain1.net,domain2.net,domain3.net,domain4.net,domain5.net,domain6.net,domain7.net,domain8.net
add,10.10.10.0/27,priority.io,,,,,,,,
CSV_EOF
echo "  Created: input/new.csv"
echo "  Format: Fixed columns (domain1-domain8)"
echo ""
cat "$PROJECT_ROOT/input/new.csv"
echo ""

##############################################################################
# Update CSV Parser for fixed columns
##############################################################################
echo "=== Updating CSV Parser for fixed columns ==="
cat > "$PROJECT_ROOT/modules/csv_parser.sh" << 'MODULE_EOF'
#!/bin/bash
set -euo pipefail

##############################################################################
# CSV Parser Module - Fixed column format
# Header: action,ip_range,domain1,domain2,domain3,domain4,domain5,domain6,domain7,domain8
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

# Process each row
LINE_NUM=0
VALID_ROWS=0
ADD_ROWS=0
REMOVE_ROWS=0
TOTAL_DOMAINS=0
TOTAL_IPS_24=0
TOTAL_IPS_27=0

echo ""
echo "Validating data rows..."

while IFS=',' read -r action ip_range domain1 domain2 domain3 domain4 domain5 domain6 domain7 domain8; do
    ((LINE_NUM++))
    
    # Skip header
    if [[ $LINE_NUM -eq 1 ]]; then
        continue
    fi
    
    # Skip completely empty lines
    if [[ -z "$action" ]] && [[ -z "$ip_range" ]]; then
        continue
    fi
    
    echo -e "  Line $LINE_NUM: action='$action', ip='$ip_range'"
    
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
    
    # Count non-empty domains
    DOMAIN_COUNT=0
    for domain in "$domain1" "$domain2" "$domain3" "$domain4" "$domain5" "$domain6" "$domain7" "$domain8"; do
        if [[ -n "$domain" ]]; then
            ((DOMAIN_COUNT++))
            echo -e "    Found domain: $domain"
        fi
    done
    
    echo -e "    Total domains: $DOMAIN_COUNT"
    
    # Validate domain count for CIDR
    if [[ "$CIDR" == "24" ]]; then
        if [[ $DOMAIN_COUNT -ne 8 ]]; then
            echo -e "${RED}    ERROR: /24 requires exactly 8 domains, found $DOMAIN_COUNT${NC}"
            continue
        fi
        TOTAL_IPS_24=$((TOTAL_IPS_24 + 254))
        echo -e "    ${GREEN}✓${NC} /24 validation passed (8 domains)"
    elif [[ "$CIDR" == "27" ]]; then
        if [[ $DOMAIN_COUNT -lt 1 ]] || [[ $DOMAIN_COUNT -gt 1 ]]; then
            echo -e "${RED}    ERROR: /27 requires exactly 1 domain, found $DOMAIN_COUNT${NC}"
            continue
        fi
        TOTAL_IPS_27=$((TOTAL_IPS_27 + 30))
        echo -e "    ${GREEN}✓${NC} /27 validation passed (1 domain)"
    elif [[ "$CIDR" == "26" ]]; then
        if [[ $DOMAIN_COUNT -lt 1 ]] || [[ $DOMAIN_COUNT -gt 2 ]]; then
            echo -e "${YELLOW}    WARNING: /26 found with $DOMAIN_COUNT domains (using first 2)${NC}"
        fi
    elif [[ "$CIDR" == "25" ]]; then
        if [[ $DOMAIN_COUNT -lt 1 ]] || [[ $DOMAIN_COUNT -gt 4 ]]; then
            echo -e "${YELLOW}    WARNING: /25 found with $DOMAIN_COUNT domains (using first 4)${NC}"
        fi
    else
        echo -e "${YELLOW}    WARNING: CIDR /$CIDR not standard (expecting /24 or /27)${NC}"
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
echo "  Updated: modules/csv_parser.sh"

##############################################################################
# Update CIDR Generator for fixed columns
##############################################################################
echo "=== Updating CIDR Generator for fixed columns ==="
cat > "$PROJECT_ROOT/modules/cidr_generator.sh" << 'MODULE_EOF'
#!/bin/bash
set -euo pipefail

##############################################################################
# CIDR Generator Module - Fixed column format
# Converts fixed column CSV to cidrs.txt for enhanced generator
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/config.sh"

INPUT_FILE="${1:-$PROJECT_ROOT/input/new.csv}"
OUTPUT_FILE="${2:-$PROJECT_ROOT/generated/cidrs.txt}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "CIDR Generator: Converting fixed-column CSV to cidrs.txt"
echo "  Input: $INPUT_FILE"
echo "  Output: $OUTPUT_FILE"

# Create header
cat > "$OUTPUT_FILE" << 'HEADER'
# CIDR blocks for enhanced hostname generation
# Generated from new.csv (fixed column format)
# Format: network/mask,domain1,domain2,...

HEADER

echo "# Generated: $(date)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Process CSV (skip header)
PROCESSED=0
SKIPPED=0

tail -n +2 "$INPUT_FILE" | while IFS=',' read -r action ip_range domain1 domain2 domain3 domain4 domain5 domain6 domain7 domain8; do
    # Only process 'add' actions
    if [[ "$action" != "add" ]]; then
        echo "  Skipping $action action for $ip_range"
        ((SKIPPED++)) || true
        continue
    fi
    
    # Build domain list from non-empty columns
    domains=""
    first=true
    for domain in "$domain1" "$domain2" "$domain3" "$domain4" "$domain5" "$domain6" "$domain7" "$domain8"; do
        if [[ -n "$domain" ]]; then
            if $first; then
                domains="$domain"
                first=false
            else
                domains="$domains,$domain"
            fi
        fi
    done
    
    # Skip if no domains
    if [[ -z "$domains" ]]; then
        echo "  WARNING: No domains for $ip_range, skipping"
        ((SKIPPED++)) || true
        continue
    fi
    
    # Write to cidrs file
    echo "${ip_range},${domains}" >> "$OUTPUT_FILE"
    
    # Count domains for display
    domain_count=$(echo "$domains" | tr ',' '\n' | wc -l)
    echo "  Added: $ip_range with $domain_count domains"
    ((PROCESSED++)) || true
done

echo ""
echo "CIDR Generation Complete:"
echo "  Processed: $PROCESSED entries"
echo "  Skipped: $SKIPPED entries"
echo "  Output: $OUTPUT_FILE"

# Show preview
echo ""
echo "Preview of generated file:"
echo "----------------------------"
cat "$OUTPUT_FILE"
echo "----------------------------"

exit 0
MODULE_EOF
chmod +x "$PROJECT_ROOT/modules/cidr_generator.sh"
echo "  Updated: modules/cidr_generator.sh"

##############################################################################
# Test the complete flow
##############################################################################
echo ""
echo "=== Testing Phase 1 with fixed column format ==="
echo ""

# Run CSV parser
echo "Step 1: Testing CSV parser..."
if "$PROJECT_ROOT/modules/csv_parser.sh"; then
    echo -e "\033[0;32m✓ CSV parser works with fixed columns\033[0m"
else
    echo -e "\033[0;31m✗ CSV parser failed\033[0m"
    exit 1
fi

echo ""
echo "Step 2: Testing CIDR generator..."
if "$PROJECT_ROOT/modules/cidr_generator.sh"; then
    echo -e "\033[0;32m✓ CIDR generator works with fixed columns\033[0m"
else
    echo -e "\033[0;31m✗ CIDR generator failed\033[0m"
    exit 1
fi

echo ""
echo "=============================================="
echo "Script 5.sh Complete!"
echo "=============================================="
echo ""
echo "Changes made:"
echo "  1. Created new input/new.csv with fixed column format"
echo "  2. Updated csv_parser.sh to handle domain1-domain8 columns"
echo "  3. Updated cidr_generator.sh to process fixed columns"
echo ""
echo "New CSV format:"
echo "  action,ip_range,domain1,domain2,domain3,domain4,domain5,domain6,domain7,domain8"
echo "  - No quotes needed"
echo "  - Empty columns for unused domains"
echo "  - Simple comma-separated parsing"
echo ""
echo "Validation rules:"
echo "  - /24 blocks: Must have exactly 8 domains"
echo "  - /27 blocks: Must have exactly 1 domain"
echo "  - Other blocks: Warnings but will process"
echo ""
echo "To run full Phase 1 test:"
echo "  ./test_phase1.sh"
echo ""
