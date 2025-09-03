#!/bin/bash
set -euo pipefail

##############################################################################
# zone_parser.sh - Parse Enhanced Generator Output
# Part of MailOps Orchestrator
# Converts BIND zone format to synchronized line files
##############################################################################

input_zone="${1:-}"
output_dir="./parsed"

if [[ -z "$input_zone" ]]; then
    echo "Usage: $0 <zone_file>"
    exit 1
fi

mkdir -p "$output_dir"

# Clear output files
> "$output_dir/ip.txt"
> "$output_dir/hostname.txt"
> "$output_dir/domain.txt"
> "$output_dir/third_octet.txt"
> "$output_dir/fourth_octet.txt"
> "$output_dir/last_digit_third.txt"

echo "Zone parser - processing $input_zone"

# Parse zone file maintaining order
while read line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" ]] && continue
    
    # Extract components from zone record
    if [[ "$line" =~ "IN A" ]]; then
        hostname=$(echo "$line" | awk '{print $1}' | sed 's/\.$//')
        ip=$(echo "$line" | awk '{print $5}')
        
        # Extract domain (last two parts of hostname)
        domain=$(echo "$hostname" | rev | cut -d. -f1,2 | rev)
        
        # Extract octets
        third_octet=$(echo "$ip" | cut -d. -f3)
        fourth_octet=$(echo "$ip" | cut -d. -f4)
        last_digit_third=$(echo "$third_octet" | grep -o '.$')
        
        # Write to synchronized files (order critical!)
        echo "$ip" >> "$output_dir/ip.txt"
        echo "$hostname" >> "$output_dir/hostname.txt"
        echo "$domain" >> "$output_dir/domain.txt"
        echo "$third_octet" >> "$output_dir/third_octet.txt"
        echo "$fourth_octet" >> "$output_dir/fourth_octet.txt"
        echo "$last_digit_third" >> "$output_dir/last_digit_third.txt"
    fi
done < "$input_zone"

# Generate unique domain list
sort -u "$output_dir/domain.txt" > "$output_dir/domain_unique.txt"

echo "Zone parsing complete. Files created in $output_dir/"
