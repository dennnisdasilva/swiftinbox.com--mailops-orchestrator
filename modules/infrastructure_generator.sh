#!/bin/bash
# Infrastructure Generator Module - Creates master infrastructure.json
# Reads from parsed files, new.csv, and dkim_data.json
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
PARSED_DIR="$PROJECT_ROOT/parsed"
INPUT_CSV="$PROJECT_ROOT/input/new.csv"
DKIM_DATA="$PROJECT_ROOT/output/dkim_data.json"
OUTPUT_JSON="$PROJECT_ROOT/output/infrastructure.json"
OUTPUT_DIR="$PROJECT_ROOT/output"

echo "Infrastructure Generator Module"
echo "========================================="
echo ""

# Check prerequisites
log_info "Checking prerequisites"

if [[ ! -d "$PARSED_DIR" ]] || [[ ! -f "$PARSED_DIR/ip.txt" ]]; then
    log_error "Parsed files not found. Run zone parser first."
    exit 1
fi

if [[ ! -f "$INPUT_CSV" ]]; then
    log_error "Input CSV not found at $INPUT_CSV"
    exit 1
fi

if [[ ! -f "$DKIM_DATA" ]]; then
    log_error "DKIM data not found. Run DKIM generator first."
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Read input files
log_info "Reading input files"

# Read CSV to get CIDR and domain list
IFS=',' read -r -a csv_headers < "$INPUT_CSV"
IFS=',' read -r action ip_range domain1 domain2 domain3 domain4 domain5 domain6 domain7 domain8 < <(tail -n1 "$INPUT_CSV")

log_debug "CIDR range: $ip_range"
log_debug "Action: $action"

# Build domain array
declare -a domains=()
for i in {1..8}; do
    var="domain$i"
    if [[ -n "${!var}" ]]; then
        domains+=("${!var}")
    fi
done

log_debug "Domains: ${domains[*]}"

# Calculate IP distribution (sequential blocks)
TOTAL_IPS=254
DOMAINS_COUNT=${#domains[@]}
IPS_PER_DOMAIN=$((TOTAL_IPS / DOMAINS_COUNT))
REMAINDER=$((TOTAL_IPS % DOMAINS_COUNT))

log_info "IP Distribution: $TOTAL_IPS IPs across $DOMAINS_COUNT domains (~$IPS_PER_DOMAIN each)"

# Read parsed data into arrays
log_info "Loading parsed data"

mapfile -t ips < "$PARSED_DIR/ip.txt"
mapfile -t hostnames < "$PARSED_DIR/hostname.txt"
mapfile -t parsed_domains < "$PARSED_DIR/domain.txt"
mapfile -t third_octets < "$PARSED_DIR/third_octet.txt"
mapfile -t fourth_octets < "$PARSED_DIR/fourth_octet.txt"

# Start building infrastructure.json
log_info "Building infrastructure.json"

cat > "$OUTPUT_JSON" << EOJSON
{
  "metadata": {
    "generated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "version": "2.0.0",
    "source_files": {
      "csv": "input/new.csv",
      "zone": "generated/hostnames.zone",
      "dkim": "output/dkim_data.json"
    },
    "statistics": {
      "total_ips": ${#ips[@]},
      "total_domains": $DOMAINS_COUNT,
      "ips_per_domain": $IPS_PER_DOMAIN
    }
  },
  "cidr_allocations": [
    {
      "range": "$ip_range",
      "mask": "255.255.255.0",
      "network": "${ip_range%/*}",
      "broadcast": "${ip_range%.*}.255",
      "usable_ips": 254,
      "action": "$action",
      "domains": [
EOJSON

# Add domains to JSON
for ((i=0; i<${#domains[@]}; i++)); do
    if [[ $i -eq $((${#domains[@]} - 1)) ]]; then
        echo "        \"${domains[$i]}\"" >> "$OUTPUT_JSON"
    else
        echo "        \"${domains[$i]}\"," >> "$OUTPUT_JSON"
    fi
done

cat >> "$OUTPUT_JSON" << EOJSON
      ]
    }
  ],
  "ip_assignments": [
EOJSON

# Create IP assignments with proper distribution
log_info "Creating IP assignments"

for ((i=0; i<${#ips[@]}; i++)); do
    ip="${ips[$i]}"
    hostname="${hostnames[$i]}"
    domain="${parsed_domains[$i]}"
    third="${third_octets[$i]}"
    fourth="${fourth_octets[$i]}"
    
    # Extract hostname prefix (before first dot)
    prefix="${hostname%%.*}"
    
    # Calculate last digit of third octet
    last_digit_third=$((third % 10))
    
    # Create VMTA name and pool
    vmta_name="${domain}.c${last_digit_third}.${fourth}"
    vmta_pool="MAILWIZZ-01-GI__${prefix}-${domain}.p"
    smtp_source="vmta-${third}-${fourth}.${domain}"
    
    # Build JSON entry
    cat >> "$OUTPUT_JSON" << EOJSON
    {
      "ip": "$ip",
      "hostname": "$hostname",
      "domain": "$domain",
      "ptr": "$hostname",
      "vmta_name": "$vmta_name",
      "vmta_pool": "$vmta_pool",
      "smtp_source_host": "$smtp_source",
      "third_octet": $third,
      "fourth_octet": $fourth,
      "last_digit_third_octet": $last_digit_third,
      "server_id": $((i + 1)),
      "status": "active"
    }
EOJSON
    
    if [[ $i -lt $((${#ips[@]} - 1)) ]]; then
        echo "," >> "$OUTPUT_JSON"
    fi
done

cat >> "$OUTPUT_JSON" << EOJSON

  ],
  "domain_configurations": {
EOJSON

# Add domain configurations
log_info "Adding domain configurations"

# Read DKIM data
for ((d=0; d<${#domains[@]}; d++)); do
    domain="${domains[$d]}"
    
    # Calculate IP range for this domain
    start_ip=$((d * IPS_PER_DOMAIN + 1))
    if [[ $d -eq $((${#domains[@]} - 1)) ]]; then
        # Last domain gets remainder
        end_ip=$TOTAL_IPS
    else
        end_ip=$(((d + 1) * IPS_PER_DOMAIN))
    fi
    
    # Extract DKIM info from dkim_data.json
        dkim_public_key=$(jq -r ".domains[\"$domain\"].public_key" "$DKIM_DATA" 2>/dev/null || echo "")
    
    cat >> "$OUTPUT_JSON" << EOJSON
    "$domain": {
      "total_ips": $((end_ip - start_ip + 1)),
      "ip_range": {
        "start": "${ip_range%.*}.${start_ip}",
        "end": "${ip_range%.*}.${end_ip}"
      },
      "dkim": {
        "selector": "key1",
        "key_size": 2048,
        "private_key_path": "/etc/pmta/domainkeys/key1.${domain}.pem",
        "backup_key_path": "$PROJECT_ROOT/output/keys/private/key1.${domain}.pem",
        "public_key": "$dkim_public_key"
      },
      "dns": {
        "spf": "v=spf1 ip4:${ip_range} ~all",
        "dmarc": "v=DMARC1; p=none; rua=mailto:dmarc@${domain}",
        "mx": {
          "priority": 10,
          "hostname": "mail.${domain}"
        }
      },
      "tracking": {
        "domain": "track.${domain}",
        "ssl_enabled": false
      },
      "bounce": {
        "hostname": "bounce.${domain}",
        "email": "bounce@${domain}",
        "imap": {
          "host": "${ip_range%.*}.${start_ip}",
          "port": 143,
          "ssl": false
        }
      }
    }
EOJSON
    
    if [[ $d -lt $((${#domains[@]} - 1)) ]]; then
        echo "," >> "$OUTPUT_JSON"
    fi
done

# Close JSON
cat >> "$OUTPUT_JSON" << EOJSON

  }
}
EOJSON

log_success "Infrastructure.json created successfully"

# Validate JSON
if command -v jq >/dev/null 2>&1; then
    if jq empty "$OUTPUT_JSON" 2>/dev/null; then
        log_success "JSON validation passed"
        
        # Show summary
        echo ""
        echo "Infrastructure Summary:"
        echo "----------------------"
        echo "Total IPs: $(jq '.metadata.statistics.total_ips' "$OUTPUT_JSON")"
        echo "Total domains: $(jq '.metadata.statistics.total_domains' "$OUTPUT_JSON")"
        echo "IP assignments: $(jq '.ip_assignments | length' "$OUTPUT_JSON")"
        echo "Domain configs: $(jq '.domain_configurations | length' "$OUTPUT_JSON")"
    else
        log_error "JSON validation failed"
        exit 1
    fi
else
    log_info "jq not installed, skipping JSON validation"
fi

echo ""
echo "Output file: $OUTPUT_JSON"
echo "========================================="
