#!/bin/bash
#############################################################################
# csv_processor.sh - Production CSV Processor for MailWizz Infrastructure
# Supports --debug flag for verbose output
#############################################################################

set -euo pipefail

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Check for debug flag BEFORE sourcing config
DEBUG_FLAG=false
if [[ "${1:-}" == "--debug" ]]; then
    DEBUG_FLAG=true
    shift  # Remove --debug from arguments
    set -x  # Enable bash debug mode
fi

# Source configuration
source ../config.sh

# Override config's DEBUG with command line flag
DEBUG=$DEBUG_FLAG

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Files and paths
INPUT_CSV="${1:-../input/new.csv}"
OUTPUT_DIR="../output"
STATE_FILE="../state/ip_distribution.json"
LOG_FILE="../logs/csv_processor_$(date +%Y%m%d_%H%M%S).log"

# Create directories
mkdir -p ../logs
mkdir -p ../state
mkdir -p "$OUTPUT_DIR"
mkdir -p ../temp

# Setup logging
if [[ "$DEBUG" == true ]]; then
    # In debug mode, show on screen and log
    exec 2>&1 | tee -a "$LOG_FILE"
fi

echo "========================================="
echo " CSV Processor - IP Distribution"
echo " Started: $(date)"
if [[ "$DEBUG" == true ]]; then
    echo " DEBUG MODE ENABLED"
fi
echo "========================================="
echo ""

# Check input
if [ ! -f "$INPUT_CSV" ]; then
    echo -e "${RED}ERROR: Input CSV not found: $INPUT_CSV${NC}"
    exit 1
fi

echo "Configuration:"
echo "  MAX_IPS_PER_DOMAIN: $MAX_IPS_PER_DOMAIN"
echo "  Debug Mode: $DEBUG"
echo ""

#############################################################################
# Parse CSV
#############################################################################
echo "Processing CSV input..."

# Read CSV and group domains by CIDR
declare -A cidr_groups
while IFS=',' read -r domain action ip_range; do
    # Skip header
    [[ "$domain" == "domain" ]] && continue
    [[ -z "$domain" ]] && continue
    
    # Clean whitespace
    domain=$(echo "$domain" | xargs)
    ip_range=$(echo "$ip_range" | xargs)
    
    if [[ "$DEBUG" == true ]]; then
        echo "  Found: $domain ($ip_range)"
    fi
    
    # Group domains by their CIDR block
    if [[ -n "${cidr_groups[$ip_range]:-}" ]]; then
        cidr_groups[$ip_range]="${cidr_groups[$ip_range]},$domain"
    else
        cidr_groups[$ip_range]="$domain"
    fi
done < "$INPUT_CSV"

echo ""

# Initialize state file
echo "{" > "$STATE_FILE"
echo '  "generated": "'$(date -Iseconds)'",' >> "$STATE_FILE"
echo '  "config": {' >> "$STATE_FILE"
echo '    "max_ips_per_domain": '$MAX_IPS_PER_DOMAIN >> "$STATE_FILE"
echo '  },' >> "$STATE_FILE"
echo '  "allocations": {' >> "$STATE_FILE"

FIRST_ALLOCATION=true
TOTAL_DOMAINS=0
TOTAL_IPS=0

#############################################################################
# Process each CIDR block
#############################################################################
for cidr in "${!cidr_groups[@]}"; do
    echo "Processing CIDR: $cidr"
    
    # Get domains for this CIDR
    IFS=',' read -ra domains <<< "${cidr_groups[$cidr]}"
    num_domains=${#domains[@]}
    
    echo "  Domains sharing this block: $num_domains"
    if [[ "$DEBUG" == true ]]; then
        for d in "${domains[@]}"; do
            echo "    - $d"
        done
    fi
    
    # Generate IPs based on CIDR mask
    network=${cidr%/*}
    mask=${cidr#*/}
    IFS='.' read -r o1 o2 o3 o4 <<< "$network"
    
    # Clear IP file
    > ../temp/ips_current.txt
    
    case $mask in
        24)
            if [[ "$DEBUG" == true ]]; then
                echo "  Generating IPs from $o1.$o2.$o3.2 to $o1.$o2.$o3.254"
            fi
            for i in {2..254}; do
                echo "$o1.$o2.$o3.$i" >> ../temp/ips_current.txt
            done
            ;;
        27)
            if [[ "$DEBUG" == true ]]; then
                echo "  Generating IPs from $o1.$o2.$o3.2 to $o1.$o2.$o3.30"
            fi
            for i in {2..30}; do
                echo "$o1.$o2.$o3.$i" >> ../temp/ips_current.txt
            done
            ;;
        28)
            for i in {2..14}; do
                echo "$o1.$o2.$o3.$i" >> ../temp/ips_current.txt
            done
            ;;
        25)
            for i in {2..126}; do
                echo "$o1.$o2.$o3.$i" >> ../temp/ips_current.txt
            done
            ;;
        26)
            for i in {2..62}; do
                echo "$o1.$o2.$o3.$i" >> ../temp/ips_current.txt
            done
            ;;
        *)
            echo "  ERROR: Unsupported mask /$mask"
            continue
            ;;
    esac
    
    total_ips=$(wc -l < ../temp/ips_current.txt)
    echo "  Total usable IPs: $total_ips"
    
    # Calculate IPs per domain
    ips_per_domain=$((total_ips / num_domains))
    if [ $ips_per_domain -gt $MAX_IPS_PER_DOMAIN ]; then
        ips_per_domain=$MAX_IPS_PER_DOMAIN
    fi
    echo "  IPs per domain: $ips_per_domain"
    
    # Distribute IPs sequentially
    line_num=1
    for domain in "${domains[@]}"; do
        output_file="$OUTPUT_DIR/${domain}_ips.txt"
        
        # Calculate range
        start=$line_num
        end=$((line_num + ips_per_domain - 1))
        
        if [[ "$DEBUG" == true ]]; then
            echo "    Allocating lines $start-$end to $domain"
        fi
        
        # Extract IPs for this domain
        sed -n "${start},${end}p" ../temp/ips_current.txt > "$output_file"
        
        # Get stats
        count=$(wc -l < "$output_file")
        if [ $count -gt 0 ]; then
            first=$(head -n1 "$output_file")
            last=$(tail -n1 "$output_file")
            
            echo "    $domain: $count IPs ($first - $last)"
            
            # Add to state file
            if [ "$FIRST_ALLOCATION" = true ]; then
                FIRST_ALLOCATION=false
            else
                echo "," >> "$STATE_FILE"
            fi
            
            echo -n "    \"$domain\": {" >> "$STATE_FILE"
            echo -n "\"count\": $count, " >> "$STATE_FILE"
            echo -n "\"first\": \"$first\", " >> "$STATE_FILE"
            echo -n "\"last\": \"$last\"}" >> "$STATE_FILE"
            
            TOTAL_DOMAINS=$((TOTAL_DOMAINS + 1))
            TOTAL_IPS=$((TOTAL_IPS + count))
            line_num=$((end + 1))
        fi
    done
    
    echo ""
done

# Close state file
echo "" >> "$STATE_FILE"
echo "  }" >> "$STATE_FILE"
echo "}" >> "$STATE_FILE"

#############################################################################
# Generate report
#############################################################################
REPORT_FILE="../output/allocation_report.txt"
cat > "$REPORT_FILE" << EOF
IP Allocation Report
Generated: $(date)
=========================================
Total Domains: $TOTAL_DOMAINS
Total IPs: $TOTAL_IPS

Domain Allocations:
EOF

for file in "$OUTPUT_DIR"/*_ips.txt; do
    if [ -f "$file" ]; then
        domain=$(basename "$file" _ips.txt)
        count=$(wc -l < "$file")
        first=$(head -n1 "$file")
        last=$(tail -n1 "$file")
        echo "  $domain: $count IPs ($first - $last)" >> "$REPORT_FILE"
    fi
done

echo "========================================="
echo -e "${GREEN}✓ Complete!${NC}"
echo "  Domains: $TOTAL_DOMAINS"
echo "  Total IPs: $TOTAL_IPS"
echo "  Report: $REPORT_FILE"

if [[ "$DEBUG" == true ]]; then
    echo ""
    echo "Debug Information:"
    echo "  Log file: $LOG_FILE"
    echo "  State file: $STATE_FILE"
    echo "  Temp files in: ../temp/"
    
    echo ""
    echo "Temp files created:"
    ls -la ../temp/*.txt 2>/dev/null || echo "  No temp files"
fi

