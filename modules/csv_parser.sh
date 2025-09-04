#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/config.sh"

INPUT_FILE="${1:-$PROJECT_ROOT/input/new.csv}"

echo -e "${CYAN}================================${NC}"
echo -e "${CYAN}CSV Parser - Validation Module${NC}"
echo -e "${CYAN}================================${NC}"
echo ""
echo "Input: $INPUT_FILE"

# Check file exists
if [[ ! -f "$INPUT_FILE" ]]; then
    echo -e "${RED}ERROR: Input file not found${NC}"
    exit 1
fi

# Validate header
EXPECTED="action,ip_range,domain1,domain2,domain3,domain4,domain5,domain6,domain7,domain8"
HEADER=$(head -1 "$INPUT_FILE")
if [[ "$HEADER" != "$EXPECTED" ]]; then
    echo -e "${RED}ERROR: Invalid header${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Header OK${NC}"
echo ""
echo "Processing rows..."
echo ""

# Use awk to properly parse CSV with empty fields
awk -F',' '
BEGIN {
    add_count = 0
    remove_count = 0
    total_ips = 0
}
NR > 1 {
    action = $1
    ip_range = $2
    
    # Count domains (fields 3-10)
    domain_count = 0
    for (i = 3; i <= 10; i++) {
        if ($i != "") domain_count++
    }
    
    # Determine IP count
    if (ip_range ~ /\/24$/) {
        ip_count = 256
        expected = 8
    } else if (ip_range ~ /\/27$/) {
        ip_count = 32
        expected = 1
    } else {
        ip_count = 0
        expected = 0
    }
    
    # Process action
    if (action == "add") {
        add_count++
        total_ips += ip_count
        printf "  \033[0;32m[ADD]\033[0m %s - %d domains, %d IPs\n", ip_range, domain_count, ip_count
        if (expected > 0 && domain_count != expected) {
            printf "    \033[1;33m⚠ Expected %d domains\033[0m\n", expected
        }
    } else if (action == "remove") {
        remove_count++
        printf "  \033[1;33m[REMOVE]\033[0m %s\n", ip_range
    }
}
END {
    printf "\n"
    printf "Summary:\n"
    printf "  Add actions: %d\n", add_count
    printf "  Remove actions: %d\n", remove_count
    printf "  Total IPs: %d\n", total_ips
}
' "$INPUT_FILE"

echo ""
echo -e "${GREEN}✓ Validation complete${NC}"
exit 0
