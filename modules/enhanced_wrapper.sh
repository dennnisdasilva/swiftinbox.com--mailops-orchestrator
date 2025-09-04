#!/bin/bash
set -euo pipefail

##############################################################################
# Enhanced Generator Wrapper Module
# Executes the existing enhanced hostname generator
# Input: cidrs.txt
# Output: hostnames.zone
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/config.sh"

# Files
INPUT_FILE="${1:-$PROJECT_ROOT/generated/cidrs.txt}"
OUTPUT_FILE="${2:-$PROJECT_ROOT/generated/hostnames.zone}"
GENERATOR="$PROJECT_ROOT/existing_scripts/generate-enhanced/generate-enhanced.sh"

echo "Enhanced Generator Wrapper"
echo "  Input: $INPUT_FILE"
echo "  Output: $OUTPUT_FILE"
echo "  Generator: $GENERATOR"

# Check generator exists
if [[ ! -f "$GENERATOR" ]]; then
    echo "ERROR: Enhanced generator not found at $GENERATOR"
    echo "       The enhanced generator must be installed first"
    exit 1
fi

if [[ ! -x "$GENERATOR" ]]; then
    echo "ERROR: Enhanced generator is not executable"
    echo "       Run: chmod +x $GENERATOR"
    exit 1
fi

# Check input file
if [[ ! -f "$INPUT_FILE" ]]; then
    echo "ERROR: Input file not found: $INPUT_FILE"
    echo "       Run cidr_generator.sh first"
    exit 1
fi

# Run the generator
echo ""
echo "Executing enhanced generator..."
echo "This may take a moment for large IP blocks..."

if "$GENERATOR" "$INPUT_FILE" > "$OUTPUT_FILE" 2>&1; then
    echo "✓ Generator completed successfully"
else
    echo "ERROR: Generator failed. Output:"
    tail -20 "$OUTPUT_FILE"
    exit 1
fi

# Verify output
if [[ ! -s "$OUTPUT_FILE" ]]; then
    echo "ERROR: Generator produced no output"
    exit 1
fi

# Statistics
RECORD_COUNT=$(grep -c "IN A" "$OUTPUT_FILE" || echo "0")
UNIQUE_HOSTNAMES=$(grep "IN A" "$OUTPUT_FILE" | awk '{print $1}' | sort -u | wc -l || echo "0")
UNIQUE_IPS=$(grep "IN A" "$OUTPUT_FILE" | awk '{print $5}' | sort -u | wc -l || echo "0")

echo ""
echo "Generation Statistics:"
echo "  Total A records: $RECORD_COUNT"
echo "  Unique hostnames: $UNIQUE_HOSTNAMES"
echo "  Unique IPs: $UNIQUE_IPS"

# Show sample output
echo ""
echo "Sample generated hostnames:"
echo "----------------------------"
grep "IN A" "$OUTPUT_FILE" | head -5
echo "----------------------------"

exit 0
