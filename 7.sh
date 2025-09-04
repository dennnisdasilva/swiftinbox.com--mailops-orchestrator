#!/bin/bash
set -euo pipefail

##############################################################################
# Just fix the csv_parser.sh to read 10 fields instead of 3
##############################################################################

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Backup the broken one
cp "$PROJECT_ROOT/modules/csv_parser.sh" "$PROJECT_ROOT/modules/csv_parser.sh.broken"

# Fix it - just change the read line to read 10 fields
sed -i 's/while IFS=.*/while IFS=, read -r action ip_range domain1 domain2 domain3 domain4 domain5 domain6 domain7 domain8; do/' "$PROJECT_ROOT/modules/csv_parser.sh"

# Fix the header check
sed -i 's/EXPECTED_HEADER=.*/EXPECTED_HEADER="action,ip_range,domain1,domain2,domain3,domain4,domain5,domain6,domain7,domain8"/' "$PROJECT_ROOT/modules/csv_parser.sh"

# Fix the domain counting logic - replace the domains_raw parsing with counting the 8 fields
sed -i '/domains_raw=/,/DOMAIN_COUNT=/c\
    # Count non-empty domains\
    DOMAIN_COUNT=0\
    [[ -n "$domain1" ]] && ((DOMAIN_COUNT++))\
    [[ -n "$domain2" ]] && ((DOMAIN_COUNT++))\
    [[ -n "$domain3" ]] && ((DOMAIN_COUNT++))\
    [[ -n "$domain4" ]] && ((DOMAIN_COUNT++))\
    [[ -n "$domain5" ]] && ((DOMAIN_COUNT++))\
    [[ -n "$domain6" ]] && ((DOMAIN_COUNT++))\
    [[ -n "$domain7" ]] && ((DOMAIN_COUNT++))\
    [[ -n "$domain8" ]] && ((DOMAIN_COUNT++))' "$PROJECT_ROOT/modules/csv_parser.sh"

echo "Fixed csv_parser.sh"
echo "Testing..."

"$PROJECT_ROOT/modules/csv_parser.sh"
