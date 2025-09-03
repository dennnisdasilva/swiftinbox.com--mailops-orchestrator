#!/bin/bash
#############################################################################
# validate_phase1.sh - Test Validator for Phase 1 Features Only
# Tests ONLY what has been implemented in CSV processor
#############################################################################

set -euo pipefail

source ../config.sh

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test scenario
SCENARIO="${1:-production.csv}"
TEST_FILE="../test_data/$SCENARIO"

echo "========================================================================="
echo " Phase 1 Validation - CSV Processing & IP Distribution"
echo "========================================================================="
echo ""
echo -e "${CYAN}Test Scenario: $SCENARIO${NC}"
echo "Configuration:"
echo "  MAX_IPS_PER_DOMAIN: $MAX_IPS_PER_DOMAIN"
echo "  SKIP_FIRST_IP: $SKIP_FIRST_IP"
echo ""

# Check test file exists
if [ ! -f "$TEST_FILE" ]; then
    echo -e "${RED}ERROR: Test file not found: $TEST_FILE${NC}"
    exit 1
fi

# Copy test data to input
cp "$TEST_FILE" ../input/new.csv

# Clean previous outputs
rm -rf ../output/*
rm -rf ../state/*
rm -rf ../logs/*

echo -e "${BLUE}Running CSV processor...${NC}"
echo "-----------------------------------------"

# Run the CSV processor
if ./csv_processor.sh; then
    echo -e "${GREEN}✓ CSV processor executed successfully${NC}"
else
    echo -e "${RED}✗ CSV processor failed${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Validating Phase 1 Features...${NC}"
echo "-----------------------------------------"

#############################################################################
# Test 1: State File Creation
#############################################################################
echo -n "TEST 1: State file created ... "
if [ -f "../state/ip_distribution.json" ]; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

#############################################################################
# Test 2: Allocation Report Created
#############################################################################
echo -n "TEST 2: Allocation report created ... "
if [ -f "../output/allocation_report.txt" ]; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

#############################################################################
# Test 3: Domain IP Files Created
#############################################################################
echo -n "TEST 3: Domain IP files created ... "
domain_count=$(grep -c "^[^d].*,enable," "$TEST_FILE" 2>/dev/null || echo 0)
ip_files_count=$(ls -1 ../output/*_ips.txt 2>/dev/null | wc -l)

if [ "$ip_files_count" -eq "$domain_count" ]; then
    echo -e "${GREEN}PASS${NC} ($ip_files_count files)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC} (Expected: $domain_count, Found: $ip_files_count)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

#############################################################################
# Test 4: No .1 Addresses Allocated
#############################################################################
echo -n "TEST 4: No .1 addresses allocated ... "
if grep -h "\.1$" ../output/*_ips.txt 2>/dev/null; then
    echo -e "${RED}FAIL${NC} (Found .1 addresses)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

#############################################################################
# Test 5: No .0 Addresses Allocated
#############################################################################
echo -n "TEST 5: No .0 addresses allocated ... "
if grep -h "\.0$" ../output/*_ips.txt 2>/dev/null; then
    echo -e "${RED}FAIL${NC} (Found .0 addresses)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

#############################################################################
# Test 6: No .255 Addresses in /24 blocks
#############################################################################
echo -n "TEST 6: No .255 addresses in /24 blocks ... "
# This is tricky - only check if we have /24 blocks
has_24_block=$(grep "/24" "$TEST_FILE" 2>/dev/null || echo "")
if [ -n "$has_24_block" ]; then
    if grep -h "\.255$" ../output/*_ips.txt 2>/dev/null; then
        echo -e "${RED}FAIL${NC} (Found .255 addresses)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
else
    echo -e "${YELLOW}SKIP${NC} (No /24 blocks)"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
fi

#############################################################################
# Test 7: MAX_IPS_PER_DOMAIN Respected
#############################################################################
echo -n "TEST 7: MAX_IPS_PER_DOMAIN limit respected ... "
violation_found=false
for ip_file in ../output/*_ips.txt; do
    if [ -f "$ip_file" ]; then
        count=$(wc -l < "$ip_file")
        if [ "$count" -gt "$MAX_IPS_PER_DOMAIN" ]; then
            violation_found=true
            domain=$(basename "$ip_file" _ips.txt)
            echo -e "${RED}FAIL${NC} ($domain has $count IPs)"
            break
        fi
    fi
done

if [ "$violation_found" = false ]; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

#############################################################################
# Test 8: Sequential Distribution
#############################################################################
echo -n "TEST 8: Sequential IP distribution ... "
# Check if domains share a CIDR block
shared_blocks=$(cut -d',' -f3 "$TEST_FILE" | grep -v "ip_range" | sort | uniq -d)

if [ -n "$shared_blocks" ]; then
    # Get first shared block
    first_block=$(echo "$shared_blocks" | head -n1)
    
    # Get domains sharing this block
    domains_in_block=$(grep "$first_block" "$TEST_FILE" | cut -d',' -f1)
    
    # Convert to array
    domain_array=($domains_in_block)
    
    if [ ${#domain_array[@]} -ge 2 ]; then
        # Check sequential between first two domains
        domain1="${domain_array[0]}"
        domain2="${domain_array[1]}"
        
        if [ -f "../output/${domain1}_ips.txt" ] && [ -f "../output/${domain2}_ips.txt" ]; then
            last_ip_d1=$(tail -n1 "../output/${domain1}_ips.txt" | cut -d. -f4)
            first_ip_d2=$(head -n1 "../output/${domain2}_ips.txt" | cut -d. -f4)
            
            expected_next=$((last_ip_d1 + 1))
            
            if [ "$first_ip_d2" -eq "$expected_next" ] || [ "$expected_next" -gt 254 ]; then
                echo -e "${GREEN}PASS${NC}"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "${RED}FAIL${NC} (Gap: .$last_ip_d1 -> .$first_ip_d2)"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
        else
            echo -e "${YELLOW}SKIP${NC} (Files missing)"
            TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        fi
    else
        echo -e "${YELLOW}SKIP${NC} (Not enough domains in block)"
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    fi
else
    echo -e "${YELLOW}SKIP${NC} (No shared blocks)"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
fi

#############################################################################
# Test 9: State File Valid JSON
#############################################################################
echo -n "TEST 9: State file is valid JSON ... "
if jq empty ../state/ip_distribution.json 2>/dev/null; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

#############################################################################
# Test 10: All Domains Have Allocations
#############################################################################
echo -n "TEST 10: All domains have IP allocations ... "
domains_in_csv=$(grep -v "^domain," "$TEST_FILE" | cut -d',' -f1 | sort -u | wc -l)
domains_in_state=$(jq -r '.allocations | keys | length' ../state/ip_distribution.json 2>/dev/null || echo 0)

if [ "$domains_in_csv" -eq "$domains_in_state" ]; then
    echo -e "${GREEN}PASS${NC} ($domains_in_state domains)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC} (CSV: $domains_in_csv, State: $domains_in_state)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""
echo -e "${BLUE}Features Not Yet Implemented (Phase 2+):${NC}"
echo "-----------------------------------------"
echo -e "${MAGENTA}• Enhanced hostname generation${NC}"
echo -e "${MAGENTA}• Zone file parsing${NC}"
echo -e "${MAGENTA}• PowerMTA configuration${NC}"
echo -e "${MAGENTA}• DKIM key generation${NC}"
echo -e "${MAGENTA}• DNS record creation${NC}"
echo -e "${MAGENTA}• Mailbox provisioning${NC}"
echo -e "${MAGENTA}• Database synchronization${NC}"

echo ""
echo "========================================================================="
echo " PHASE 1 TEST RESULTS"
echo "========================================================================="

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))

echo "  Total Tests: $TOTAL_TESTS"
echo -e "  Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "  Failed: ${RED}$TESTS_FAILED${NC}"
echo -e "  Skipped: ${YELLOW}$TESTS_SKIPPED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    PASS_RATE=100
else
    PASS_RATE=$((TESTS_PASSED * 100 / (TESTS_PASSED + TESTS_FAILED)))
fi

echo "  Pass Rate: $PASS_RATE%"
echo ""

# Show sample output for verification
echo -e "${BLUE}Sample Output (first domain):${NC}"
echo "-----------------------------------------"
first_domain=$(ls ../output/*_ips.txt 2>/dev/null | head -n1)
if [ -n "$first_domain" ]; then
    domain_name=$(basename "$first_domain" _ips.txt)
    ip_count=$(wc -l < "$first_domain")
    first_5=$(head -n5 "$first_domain")
    last_5=$(tail -n5 "$first_domain")
    
    echo "Domain: $domain_name"
    echo "Total IPs: $ip_count"
    echo "First 5 IPs:"
    echo "$first_5" | sed 's/^/  /'
    echo "Last 5 IPs:"
    echo "$last_5" | sed 's/^/  /'
fi

echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ Phase 1 CSV Processing is working correctly!${NC}"
    echo ""
    echo "Ready to proceed to Phase 2: Enhanced Generator Integration"
    exit 0
else
    echo -e "${RED}✗ Phase 1 has issues that need fixing${NC}"
    echo ""
    echo "Review the failed tests above and check logs in: ../logs/"
    exit 1
fi

