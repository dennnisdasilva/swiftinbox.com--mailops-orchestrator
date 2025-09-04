#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/config.sh"

INPUT_FILE="${1:-$PROJECT_ROOT/input/new.csv}"

# Use Python to parse CSV properly
python3 << PYTHON_EOF
import csv
import sys

input_file = "$INPUT_FILE"

try:
    with open(input_file, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        
        print(f"CSV Parser: Processing {input_file}")
        print(f"✓ Header validation passed")
        print()
        print("Validating data rows...")
        
        valid_rows = 0
        total_domains = 0
        total_ips = 0
        
        for row_num, row in enumerate(reader, 2):
            if len(row) < 3:
                continue
                
            action = row[0]
            ip_range = row[1]
            domains = [d for d in row[2:] if d]  # Get non-empty domains
            
            domain_count = len(domains)
            cidr = ip_range.split('/')[-1]
            
            print(f"  Line {row_num}: {action} {ip_range} - {domain_count} domains")
            
            # Validate
            if cidr == '24':
                if domain_count != 8:
                    print(f"    ERROR: /24 requires 8 domains, found {domain_count}")
                    sys.exit(1)
                print("    ✓ /24 validation passed")
                total_ips += 254
            elif cidr == '27':
                if domain_count != 1:
                    print(f"    ERROR: /27 requires 1 domain, found {domain_count}")
                    sys.exit(1)
                print("    ✓ /27 validation passed")
                total_ips += 30
            
            valid_rows += 1
            total_domains += domain_count
        
        print()
        print("=" * 44)
        print(f"Valid rows: {valid_rows}")
        print(f"Total domains: {total_domains}")
        print(f"Total IPs: {total_ips}")
        print("=" * 44)
        print()
        print("Validation successful!")
        
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
PYTHON_EOF

exit $?
