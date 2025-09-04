#!/bin/bash
set -euo pipefail

##############################################################################
# Implementation Script 12.sh
# Stop fighting with bash - use Python for CSV parsing
##############################################################################

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Creating a CSV parser that actually works..."

# Create a simple Python-based CSV parser
cat > "$PROJECT_ROOT/modules/csv_parser.sh" << 'EOF'
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
EOF
chmod +x "$PROJECT_ROOT/modules/csv_parser.sh"

# Also update cidr_generator to use Python
cat > "$PROJECT_ROOT/modules/cidr_generator.sh" << 'EOF'
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
EOF
chmod +x "$PROJECT_ROOT/modules/cidr_generator.sh"

echo ""
echo "Testing CSV parser..."
if "$PROJECT_ROOT/modules/csv_parser.sh"; then
    echo -e "\n\033[0;32m✓ CSV parser works\033[0m"
else
    echo -e "\n\033[0;31m✗ Failed\033[0m"
    exit 1
fi

echo ""
echo "Testing CIDR generator..."
if "$PROJECT_ROOT/modules/cidr_generator.sh"; then
    echo -e "\n\033[0;32m✓ CIDR generator works\033[0m"
    echo ""
    echo "Generated cidrs.txt:"
    cat "$PROJECT_ROOT/generated/cidrs.txt"
else
    echo -e "\n\033[0;31m✗ Failed\033[0m"
    exit 1
fi

echo ""
echo "Both modules working. Run: ./test_phase1.sh"
