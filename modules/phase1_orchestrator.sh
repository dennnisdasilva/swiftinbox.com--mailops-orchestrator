#!/bin/bash
set -euo pipefail

##############################################################################
# Phase 1 Orchestrator
# Runs the complete Phase 1 data flow:
# new.csv → cidrs.txt → enhanced generator → zone file → parsed files
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/config.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}============================================${NC}"
echo -e "${BOLD}${BLUE}    Phase 1: Data Flow Foundation${NC}"
echo -e "${BOLD}${BLUE}============================================${NC}"
echo ""

# Check for input file
INPUT_FILE="$PROJECT_ROOT/input/new.csv"
if [[ ! -f "$INPUT_FILE" ]]; then
    echo -e "${RED}ERROR: Input file not found: $INPUT_FILE${NC}"
    echo ""
    echo "Please create input/new.csv with format:"
    echo "  action,ip_range,domains"
    echo "  add,6.6.6.0/24,\"domain1.net,domain2.net,...(8 domains)\""
    echo "  add,10.10.10.0/27,\"priority.io\""
    exit 1
fi

# Step 1: Validate CSV
echo -e "${BOLD}[Step 1/4] Validating CSV input${NC}"
if "$PROJECT_ROOT/modules/csv_parser.sh" "$INPUT_FILE"; then
    echo -e "${GREEN}✓ CSV validation complete${NC}"
else
    echo -e "${RED}✗ CSV validation failed${NC}"
    exit 1
fi

echo ""
read -p "Press Enter to continue to CIDR generation..."

# Step 2: Generate CIDR file
echo -e "${BOLD}[Step 2/4] Generating CIDR file${NC}"
if "$PROJECT_ROOT/modules/cidr_generator.sh" "$INPUT_FILE"; then
    echo -e "${GREEN}✓ CIDR generation complete${NC}"
else
    echo -e "${RED}✗ CIDR generation failed${NC}"
    exit 1
fi

echo ""
read -p "Press Enter to continue to hostname generation..."

# Step 3: Run enhanced generator
echo -e "${BOLD}[Step 3/4] Running enhanced hostname generator${NC}"
if "$PROJECT_ROOT/modules/enhanced_wrapper.sh"; then
    echo -e "${GREEN}✓ Hostname generation complete${NC}"
else
    echo -e "${RED}✗ Hostname generation failed${NC}"
    exit 1
fi

echo ""
read -p "Press Enter to continue to zone parsing..."

# Step 4: Parse zone to files
echo -e "${BOLD}[Step 4/4] Parsing zone to synchronized files${NC}"
if "$PROJECT_ROOT/modules/zone_to_files.sh"; then
    echo -e "${GREEN}✓ Zone parsing complete${NC}"
else
    echo -e "${RED}✗ Zone parsing failed${NC}"
    exit 1
fi

# Summary
echo ""
echo -e "${BOLD}${GREEN}============================================${NC}"
echo -e "${BOLD}${GREEN}    Phase 1 Complete!${NC}"
echo -e "${BOLD}${GREEN}============================================${NC}"
echo ""
echo "Generated files:"
echo "  - generated/cidrs.txt - Input for enhanced generator"
echo "  - generated/hostnames.zone - BIND zone format output"
echo "  - parsed/*.txt - Synchronized line files"
echo ""
echo "Key outputs in parsed/:"
ls -la "$PROJECT_ROOT/parsed/"*.txt | tail -8
echo ""
echo "Next phase will use these parsed files for:"
echo "  - PowerMTA configuration"
echo "  - DKIM key generation"
echo "  - DNS record preparation"
echo "  - Database synchronization"

exit 0
