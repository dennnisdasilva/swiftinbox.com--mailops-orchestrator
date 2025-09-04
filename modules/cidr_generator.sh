#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/config.sh"

INPUT_FILE="${1:-$PROJECT_ROOT/input/new.csv}"
OUTPUT_FILE="${2:-$PROJECT_ROOT/generated/cidrs.txt}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "CIDR Generator: Converting new.csv to cidrs.txt"

python3 << PYTHON_EOF
import csv

input_file = "$INPUT_FILE"
output_file = "$OUTPUT_FILE"

with open(input_file, 'r') as f_in, open(output_file, 'w') as f_out:
    f_out.write("# CIDR blocks for enhanced hostname generation\n\n")
    
    reader = csv.reader(f_in)
    next(reader)  # Skip header
    
    for row in reader:
        if len(row) < 3 or row[0] != 'add':
            continue
            
        ip_range = row[1]
        domains = [d for d in row[2:] if d]
        
        if domains:
            f_out.write(f"{ip_range},{','.join(domains)}\n")
            print(f"  Added: {ip_range}")

print(f"Output: {output_file}")
PYTHON_EOF

exit $?
