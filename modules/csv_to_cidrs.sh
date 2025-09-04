#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/config.sh"

INPUT_FILE="${1:-$PROJECT_ROOT/input/new.csv}"
OUTPUT_FILE="${2:-$PROJECT_ROOT/generated/cidrs.txt}"

echo -e "${CYAN}================================${NC}"
echo -e "${CYAN}CSV to CIDRS Converter${NC}"
echo -e "${CYAN}================================${NC}"
echo ""

mkdir -p "$(dirname "$OUTPUT_FILE")"

# Create header
cat > "$OUTPUT_FILE" << 'HEADER'
# CIDR blocks for enhanced hostname generation
# Generated from new.csv
HEADER
echo "# $(date)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Converting..."
echo ""

# Use awk to handle CSV properly
awk -F',' '
NR > 1 && $1 == "add" {
    ip_range = $2
    domains = ""
    
    # Build domain list from fields 3-10
    for (i = 3; i <= 10; i++) {
        if ($i != "") {
            if (domains == "") {
                domains = $i
            } else {
                domains = domains "," $i
            }
        }
    }
    
    if (domains != "") {
        print ip_range "," domains
        printf "  Added: %s\n", ip_range
    }
}
' "$INPUT_FILE" >> "$OUTPUT_FILE"

echo ""
echo "Generated cidrs.txt:"
echo "-------------------"
cat "$OUTPUT_FILE"
echo "-------------------"
echo ""
echo -e "${GREEN}✓ Conversion complete${NC}"
exit 0
