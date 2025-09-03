#!/bin/bash
#############################################################################
# test_phase1.sh - Test Phase 1 CSV Processing
# Validates IP distribution and output formats
#############################################################################

set -euo pipefail

source ../config.sh

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================="
echo " Phase 1 Test Suite"
echo "========================================="
echo ""

# Check for input file
if [ ! -f "../input/new.csv" ]; then
    echo -e "${YELLOW}Creating sample input file...${NC}"
    mkdir -p ../input
    cat > ../input/new.csv << 'EOF'
domain,action,ip_range
domain1.net,enable,6.6.6.0/24
domain2.net,enable,6.6.6.0/24
domain3.net,enable,6.6.6.0/24
domain4.net,enable,6.6.6.0/24
domain5.net,enable,6.6.6.0/24
domain6.net,enable,6.6.6.0/24
domain7.net,enable,6.6.6.0/24
domain8.net,enable,6.6.6.0/24
priority.io,enable,10.10.10.0/27
EOF
    echo "  Created sample input/new.csv"
fi

echo -e "${BLUE}Running CSV processor...${NC}"
echo ""

./csv_processor.sh

echo ""
echo -e "${BLUE}Validating results...${NC}"

# Check state file
if [ -f "../state/ip_distribution.json" ]; then
    echo -e "${GREEN}✓${NC} State file created"
    
    # Verify allocations
    domains=$(jq -r '.allocations | keys | length' ../state/ip_distribution.json)
    echo "  Domains processed: $domains"
    
    # Check each domain
    for domain in $(jq -r '.allocations | keys[]' ../state/ip_distribution.json); do
        count=$(jq -r ".allocations[\"$domain\"].count" ../state/ip_distribution.json)
        echo "  $domain: $count IPs"
        
        # Verify output file exists
        if [ -f "../output/${domain}_ips.txt" ]; then
            file_count=$(wc -l < "../output/${domain}_ips.txt")
            if [ $file_count -eq $count ]; then
                echo -e "    ${GREEN}✓${NC} Output file matches allocation"
            else
                echo -e "    ${RED}✗${NC} Output file mismatch (expected: $count, found: $file_count)"
            fi
        else
            echo -e "    ${RED}✗${NC} Output file missing"
        fi
    done
else
    echo -e "${RED}✗${NC} State file not created"
fi

echo ""
echo -e "${BLUE}Checking IP distribution rules...${NC}"

# Verify no .1 addresses allocated
echo -n "  Checking for .1 addresses (should be skipped): "
if grep -q "\.1$" ../output/*_ips.txt 2>/dev/null; then
    echo -e "${RED}FOUND (error)${NC}"
else
    echo -e "${GREEN}None found (correct)${NC}"
fi

# Verify sequential allocation
echo -n "  Checking sequential allocation: "
first_domain_last=$(tail -n1 ../output/domain1.net_ips.txt 2>/dev/null | cut -d. -f4)
second_domain_first=$(head -n1 ../output/domain2.net_ips.txt 2>/dev/null | cut -d. -f4)
if [ -n "$first_domain_last" ] && [ -n "$second_domain_first" ]; then
    if [ $((first_domain_last + 1)) -eq $second_domain_first ]; then
        echo -e "${GREEN}Sequential (correct)${NC}"
    else
        echo -e "${YELLOW}Gap detected${NC}"
    fi
else
    echo -e "${YELLOW}Unable to verify${NC}"
fi

echo ""
echo "========================================="
echo " Test Complete"
echo "========================================="
echo ""
echo "Review the following files:"
echo "  * ../output/allocation_report.txt"
echo "  * ../state/ip_distribution.json"
echo "  * ../output/*_ips.txt"

