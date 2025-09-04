#!/bin/bash
set -euo pipefail

##############################################################################
# Zone to Files Parser Module
# Parses enhanced generator output (BIND zone format)
# Creates synchronized line-by-line files
# Input: hostnames.zone
# Output: parsed/*.txt files
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/config.sh"

# Files
INPUT_FILE="${1:-$PROJECT_ROOT/generated/hostnames.zone}"
OUTPUT_DIR="${2:-$PROJECT_ROOT/parsed}"

mkdir -p "$OUTPUT_DIR"

echo "Zone to Files Parser"
echo "  Input: $INPUT_FILE"
echo "  Output directory: $OUTPUT_DIR"

# Check input
if [[ ! -f "$INPUT_FILE" ]]; then
    echo "ERROR: Zone file not found: $INPUT_FILE"
    exit 1
fi

# Initialize output files (clear any existing)
> "$OUTPUT_DIR/ip.txt"
> "$OUTPUT_DIR/hostname.txt"
> "$OUTPUT_DIR/domain.txt"
> "$OUTPUT_DIR/third_octet.txt"
> "$OUTPUT_DIR/fourth_octet.txt"
> "$OUTPUT_DIR/last_digit_third.txt"

echo ""
echo "Parsing zone file..."

# Parse each A record
RECORD_COUNT=0
while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" ]] && continue
    
    # Only process A records
    if [[ "$line" =~ "IN A" ]]; then
        # Extract hostname and IP
        hostname=$(echo "$line" | awk '{print $1}' | sed 's/\.$//')
        ip=$(echo "$line" | awk '{print $5}')
        
        # Validate extraction
        if [[ -z "$hostname" ]] || [[ -z "$ip" ]]; then
            echo "WARNING: Failed to parse line: $line"
            continue
        fi
        
        # Extract domain (last two parts of hostname)
        domain=$(echo "$hostname" | rev | cut -d. -f1,2 | rev)
        
        # Extract IP octets
        octet1=$(echo "$ip" | cut -d. -f1)
        octet2=$(echo "$ip" | cut -d. -f2)
        octet3=$(echo "$ip" | cut -d. -f3)
        octet4=$(echo "$ip" | cut -d. -f4)
        
        # Get last digit of third octet
        last_digit_third=${octet3: -1}
        
        # Write to synchronized files (order is critical!)
        echo "$ip" >> "$OUTPUT_DIR/ip.txt"
        echo "$hostname" >> "$OUTPUT_DIR/hostname.txt"
        echo "$domain" >> "$OUTPUT_DIR/domain.txt"
        echo "$octet3" >> "$OUTPUT_DIR/third_octet.txt"
        echo "$octet4" >> "$OUTPUT_DIR/fourth_octet.txt"
        echo "$last_digit_third" >> "$OUTPUT_DIR/last_digit_third.txt"
        
        ((RECORD_COUNT++))
        
        # Progress indicator every 100 records
        if (( RECORD_COUNT % 100 == 0 )); then
            echo "  Processed $RECORD_COUNT records..."
        fi
    fi
done < "$INPUT_FILE"

# Create unique domain list
sort -u "$OUTPUT_DIR/domain.txt" > "$OUTPUT_DIR/domain_unique.txt"

# Create unique IP list
sort -u "$OUTPUT_DIR/ip.txt" > "$OUTPUT_DIR/ip_unique.txt"

echo ""
echo "Parsing Complete:"
echo "  Records processed: $RECORD_COUNT"
echo "  Files created:"
echo "    - ip.txt: $(wc -l < "$OUTPUT_DIR/ip.txt") lines"
echo "    - hostname.txt: $(wc -l < "$OUTPUT_DIR/hostname.txt") lines"
echo "    - domain.txt: $(wc -l < "$OUTPUT_DIR/domain.txt") lines"
echo "    - domain_unique.txt: $(wc -l < "$OUTPUT_DIR/domain_unique.txt") unique domains"
echo "    - ip_unique.txt: $(wc -l < "$OUTPUT_DIR/ip_unique.txt") unique IPs"
echo "    - third_octet.txt: $(wc -l < "$OUTPUT_DIR/third_octet.txt") lines"
echo "    - fourth_octet.txt: $(wc -l < "$OUTPUT_DIR/fourth_octet.txt") lines"
echo "    - last_digit_third.txt: $(wc -l < "$OUTPUT_DIR/last_digit_third.txt") lines"

# Verify synchronization
IP_LINES=$(wc -l < "$OUTPUT_DIR/ip.txt")
HOSTNAME_LINES=$(wc -l < "$OUTPUT_DIR/hostname.txt")
DOMAIN_LINES=$(wc -l < "$OUTPUT_DIR/domain.txt")

if [[ $IP_LINES -ne $HOSTNAME_LINES ]] || [[ $IP_LINES -ne $DOMAIN_LINES ]]; then
    echo ""
    echo "ERROR: File synchronization mismatch!"
    echo "  ip.txt: $IP_LINES lines"
    echo "  hostname.txt: $HOSTNAME_LINES lines"
    echo "  domain.txt: $DOMAIN_LINES lines"
    exit 1
fi

echo ""
echo "✓ File synchronization verified"

# Show sample synchronized data
echo ""
echo "Sample synchronized data (first 3 records):"
echo "-------------------------------------------"
paste "$OUTPUT_DIR/ip.txt" "$OUTPUT_DIR/hostname.txt" "$OUTPUT_DIR/domain.txt" | head -3
echo "-------------------------------------------"

exit 0
