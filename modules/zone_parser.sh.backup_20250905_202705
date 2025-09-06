#!/bin/bash
# Zone Parser Module - Parses hostnames.zone and creates parsed files
# Fixed version with correct regex and enhanced debugging
set -euo pipefail

# Get project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DEBUG="${DEBUG:-false}"

# Parse command line arguments
if [[ "${1:-}" == "--debug" ]]; then
    DEBUG=true
fi

# Logging functions
log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_debug() {
    if [[ "$DEBUG" == true ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [DEBUG] $*" >&2
    fi
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_success() {
    echo -e "\033[32m[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*\033[0m"
}

# Paths
HOSTNAMES_ZONE="$PROJECT_ROOT/generated/hostnames.zone"
INPUT_CSV="$PROJECT_ROOT/input/new.csv"
DKIM_DATA="$PROJECT_ROOT/output/dkim_data.json"
OUTPUT_JSON="$PROJECT_ROOT/output/infrastructure.json"
PARSED_DIR="$PROJECT_ROOT/parsed"

echo "Zone Parser Module"
echo "========================================="
echo ""

# Check prerequisites
if [[ ! -f "$HOSTNAMES_ZONE" ]]; then
    log_error "hostnames.zone not found at $HOSTNAMES_ZONE"
    echo "Please run Enhanced Generator first (Option 2)"
    exit 1
fi

log_info "Parsing zone file: $HOSTNAMES_ZONE"
log_debug "Debug mode: $DEBUG"

# Create parsed directory
mkdir -p "$PARSED_DIR"
log_debug "Created/verified parsed directory: $PARSED_DIR"

# Initialize output files
log_info "Initializing output files"
> "$PARSED_DIR/ip.txt"
> "$PARSED_DIR/hostname.txt"
> "$PARSED_DIR/domain.txt"
> "$PARSED_DIR/third_octet.txt"
> "$PARSED_DIR/fourth_octet.txt"

# Count total lines for progress
TOTAL_LINES=$(wc -l < "$HOSTNAMES_ZONE")
log_debug "Total lines in zone file: $TOTAL_LINES"

# Parse the zone file
log_info "Starting zone file parsing"
record_count=0
line_count=0

while IFS= read -r line; do
    line_count=$((line_count + 1))
    
    # Skip empty lines
    if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
        continue
    fi
    
    # Skip comment lines
    if [[ "$line" =~ ^[[:space:]]*\; ]]; then
        log_debug "Line $line_count: Skipping comment"
        continue
    fi
    
    # Parse A records - match multiple possible formats
    # Format 1: hostname. IN A IP
    # Format 2: hostname. TTL IN A IP
    # Format 3: hostname IN A IP (no trailing dot)
    
    if [[ "$line" =~ ([a-zA-Z0-9.-]+)\.?[[:space:]]+([0-9]+[[:space:]]+)?IN[[:space:]]+A[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
        hostname="${BASH_REMATCH[1]}"
        ip="${BASH_REMATCH[3]}"
        
        # Remove trailing dot if present
        hostname="${hostname%.}"
        
        # Extract domain from hostname (everything after first dot)
        if [[ "$hostname" =~ ^[^.]+\.(.+)$ ]]; then
            domain="${BASH_REMATCH[1]}"
        else
            domain="$hostname"
        fi
        
        # Extract octets
        IFS='.' read -r oct1 oct2 oct3 oct4 <<< "$ip"
        third_octet="$oct3"
        fourth_octet="$oct4"
        
        # Save to files
        echo "$ip" >> "$PARSED_DIR/ip.txt"
        echo "$hostname" >> "$PARSED_DIR/hostname.txt"
        echo "$domain" >> "$PARSED_DIR/domain.txt"
        echo "$third_octet" >> "$PARSED_DIR/third_octet.txt"
        echo "$fourth_octet" >> "$PARSED_DIR/fourth_octet.txt"
        
        record_count=$((record_count + 1))
        
        if [[ $((record_count % 50)) -eq 0 ]]; then
            log_debug "Processed $record_count records..."
        fi
        
        # Debug first few records
        if [[ "$DEBUG" == true ]] && [[ $record_count -le 3 ]]; then
            log_debug "Record $record_count: hostname=$hostname, domain=$domain, ip=$ip"
        fi
    else
        # Only log non-empty, non-comment lines that didn't match
        if [[ "$line" =~ [A-Za-z0-9] ]]; then
            log_debug "Line $line_count: No match for: $line"
        fi
    fi
done < "$HOSTNAMES_ZONE"

log_success "Parsed $record_count A records from zone file"

# Create domain_unique.txt
log_info "Creating unique domain list"
sort -u "$PARSED_DIR/domain.txt" > "$PARSED_DIR/domain_unique.txt"
unique_domains=$(wc -l < "$PARSED_DIR/domain_unique.txt")
log_success "Found $unique_domains unique domains"

# Display summary
echo ""
echo "Parsing Summary:"
echo "----------------"
echo "✓ Total records parsed: $record_count"
echo "✓ Unique domains: $unique_domains"
echo "✓ Files created in: $PARSED_DIR/"

# List created files with line counts
echo ""
echo "Created files:"
for file in ip.txt hostname.txt domain.txt third_octet.txt fourth_octet.txt domain_unique.txt; do
    if [[ -f "$PARSED_DIR/$file" ]]; then
        count=$(wc -l < "$PARSED_DIR/$file")
        printf "  %-20s : %d lines\n" "$file" "$count"
    fi
done

# Check if DKIM data exists for infrastructure.json creation
if [[ -f "$DKIM_DATA" ]]; then
    echo ""
    echo "Note: DKIM data found. Run infrastructure generator to create full infrastructure.json"
else
    echo ""
    echo "Note: DKIM data not found. Run DKIM processor (Option 5) before infrastructure generation"
fi

# Validation
if [[ $record_count -eq 254 ]]; then
    log_success "Zone parsing completed successfully (254 records as expected)"
    exit 0
else
    log_error "Warning: Expected 254 records but parsed $record_count"
    exit 1
fi
