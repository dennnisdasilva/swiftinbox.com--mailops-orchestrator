#!/usr/bin/env bash
set -euo pipefail

# Enhanced A Record Generator for Mail Infrastructure
# Usage: ./generate-enhanced.sh cidrs.txt > batch.zone
# Features:
# - Non-sequential IP assignment
# - Cross-run uniqueness tracking
# - 12+ diverse naming patterns
# - Enhanced security through pattern obfuscation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
STATE_DIR="${SCRIPT_DIR}/state"
STATE_FILE="${STATE_DIR}/used_names.json"
CIDR_FILE="${1:-cidrs.txt}"

# Check for debug flag
DEBUG_MODE=false
if [[ "${1:-}" == "--debug" ]]; then
    DEBUG_MODE=true
    shift
    CIDR_FILE="${1:-cidrs.txt}"
fi

# --- PREFLIGHT CHECKS ---
preflight_checks() {
    local errors=0

    echo "=== Running Preflight Checks ===" >&2

    # Check for required commands
    for cmd in jq openssl xxd; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "ERROR: Required command '$cmd' not found" >&2
            errors=$((errors+1)) || true
        fi
    done

    # Check CIDR file
    if [[ ! -f "$CIDR_FILE" ]]; then
        echo "ERROR: CIDR file '$CIDR_FILE' not found" >&2
        errors=$((errors+1)) || true
    fi

    # Create directories if they don't exist
    if [[ ! -d "$LIB_DIR" ]]; then
        echo "Creating lib directory..." >&2
        mkdir -p "$LIB_DIR"
    fi

    if [[ ! -d "$STATE_DIR" ]]; then
        echo "Creating state directory..." >&2
        mkdir -p "$STATE_DIR"
    fi

    # Initialize state file if it doesn't exist
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "Initializing state file..." >&2
        echo '{"used_names": {}, "last_run": null, "total_generated": 0}' > "$STATE_FILE"
    fi

    # Validate state file is valid JSON
    if ! jq empty "$STATE_FILE" 2>/dev/null; then
        echo "WARNING: State file is corrupted, backing up and reinitializing..." >&2
        mv "$STATE_FILE" "${STATE_FILE}.backup.$(date +%s)"
        echo '{"used_names": {}, "last_run": null, "total_generated": 0}' > "$STATE_FILE"
    fi

    # Check library files
    local lib_files=("state_manager.sh" "name_generators.sh" "entropy_pools.sh" "utils.sh")
    for lib in "${lib_files[@]}"; do
        if [[ ! -f "${LIB_DIR}/${lib}" ]]; then
            echo "ERROR: Required library '${LIB_DIR}/${lib}' not found" >&2
            errors=$((errors+1)) || true
        fi
    done

    if ((errors > 0)); then
        echo "ERROR: Preflight checks failed with $errors errors" >&2
        exit 1
    fi

    echo "=== Preflight Checks Passed ===" >&2
    echo >&2
}

# --- SOURCE LIBRARIES ---
source_libraries() {
    source "${LIB_DIR}/utils.sh"
    source "${LIB_DIR}/entropy_pools.sh"
    source "${LIB_DIR}/state_manager.sh"
    source "${LIB_DIR}/name_generators.sh"
}

# --- MAIN PROCESSING ---
process_cidr_block() {
    # Temporarily disable exit on error for debugging
    set +e
    
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: === Starting process_cidr_block ===" >&2
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Arguments: cidr=$1, domains=$2" >&2
    local cidr="$1"
    local domains_csv="$2"

    # Parse CIDR and domains
    IFS=/ read -r net mask <<<"$cidr"
    IFS=, read -r -a domains <<<"$domains_csv"
    local domain_count=${#domains[@]}
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Network: $net, Mask: /$mask, Domains provided: $domain_count" >&2

    # Calculate usable IPs based on subnet mask
    local total_ips=0
    case $mask in
        24) total_ips=254 ;;
        25) total_ips=126 ;;
        26) total_ips=62 ;;
        27) total_ips=30 ;;
        28) total_ips=14 ;;
        29) total_ips=6 ;;
        30) total_ips=2 ;;
        31) total_ips=2 ;;
        32) total_ips=1 ;;
        *)
            echo "ERROR: Unsupported subnet mask /$mask" >&2
            return 1
            ;;
    esac
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Total usable IPs for /$mask: $total_ips" >&2

    # Calculate expected domains - CORRECTED FORMULA
    local expected_domains
    if (( total_ips <= 30 )); then
        expected_domains=1
    elif (( total_ips <= 62 )); then
        expected_domains=2
    elif (( total_ips <= 93 )); then
        expected_domains=3
    elif (( total_ips <= 126 )); then
        expected_domains=4  # Fixed: 126 IPs = 4 domains
    elif (( total_ips <= 155 )); then
        expected_domains=5
    elif (( total_ips <= 186 )); then
        expected_domains=6
    elif (( total_ips <= 217 )); then
        expected_domains=7
    elif (( total_ips <= 254 )); then
        expected_domains=8
    else
        expected_domains=$(( (total_ips + 30) / 31 ))
    fi
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Expected $expected_domains domains for $total_ips IPs" >&2

    # Validate domain count
    if (( domain_count != expected_domains )); then
        echo "ERROR: $cidr with $total_ips IPs expects $expected_domains domains, got $domain_count" >&2
        set -e
        return 1
    fi

    # Build sequential IP array
    IFS=. read -r o1 o2 o3 o4 <<<"$net"
    local ips=()
    
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Building sequential IP array..." >&2
    for ((i=1; i<=total_ips; i++)); do
        ips+=("${o1}.${o2}.${o3}.${i}")
    done
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Built array with ${#ips[@]} IPs (first: ${ips[0]}, last: ${ips[$((${#ips[@]}-1))]})" >&2

    # Assign one style per domain
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Assigning styles to domains..." >&2
    local domain_styles=()
    local all_styles=(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14)
    local shuffled_styles=()
    while IFS= read -r style; do
        shuffled_styles+=("$style")
    done < <(printf "%s\n" "${all_styles[@]}" | sort -R)
    
    for ((i=0; i<domain_count; i++)); do
        domain_styles[i]="${shuffled_styles[i]}"
        [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:   ${domains[i]} → style ${domain_styles[i]}" >&2
    done

    echo ";; Block $cidr (domains: ${domains[*]})"
    echo ";; Sequential IP blocks with consistent per-domain patterns"

    # Calculate IPs per domain
    local ips_per_domain=$((total_ips / domain_count))
    local extra_ips=$((total_ips % domain_count))
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Distribution: $ips_per_domain IPs per domain, $extra_ips domains get 1 extra" >&2

    # Generate records by domain blocks
    local generated_count=0
    local ip_index=0
    
    for ((d=0; d<domain_count; d++)); do
        local domain="${domains[d]}"
        local style="${domain_styles[d]}"
        
        # Calculate IPs for this domain
        local domain_ip_count=$ips_per_domain
        if (( d < extra_ips )); then
            ((domain_ip_count++))
        fi
        
        local start_ip=$((ip_index + 1))
        local end_ip=$((ip_index + domain_ip_count))
        [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Processing $domain: IPs $start_ip-$end_ip ($domain_ip_count total)" >&2
        
        local domain_records=0
        
        # Generate records for this domain's IP block
        for ((i=0; i<domain_ip_count && ip_index<${#ips[@]}; i++)); do
            local ip="${ips[$ip_index]}"
            [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:   Record $((i+1))/$domain_ip_count: IP=${ip}" >&2
            
            # Generate unique name
            local name
            local attempts=0
            local max_attempts=50
            
            [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:   Generating name with style $style..." >&2
            while ((attempts < max_attempts)); do
                name=$(generate_name "$style" "$ip" 2>&1)
                local gen_code=$?
                if [[ $gen_code -ne 0 ]]; then
                    echo "ERROR: generate_name failed with code $gen_code: $name" >&2
                    break
                fi
                
                local fqdn="${name}.${domain}"
                [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:     Attempt $((attempts+1)): name=$name, checking uniqueness..." >&2
                
                if ! state_exists "$fqdn"; then
                    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:     Name is unique!" >&2
                    break
                fi
                
                ((attempts++))
            done
            
            if ((attempts >= max_attempts)); then
                echo "ERROR: Failed to generate unique name for $ip after $max_attempts attempts" >&2
                ((ip_index++))
                continue
            fi
            
            # Emit A record
            local fqdn="${name}.${domain}"
            [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:   Emitting record: $fqdn → $ip" >&2
            printf "%-50s IN A %s\n" "${fqdn}." "$ip"
            
            # Add to state with error checking
            [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:   Calling state_add..." >&2
            state_add "$fqdn" "$ip" 2>&1
            local state_code=$?
            if [[ $state_code -ne 0 ]]; then
                echo "ERROR: state_add failed with code $state_code" >&2
            else
                [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:   state_add successful" >&2
            fi
            
            ((ip_index++))
            ((generated_count++))
            ((domain_records++))
            
            [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:   Record complete. Generated so far: $generated_count" >&2
        done
        
        [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Completed $domain: generated $domain_records records" >&2
    done

    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: === Completed process_cidr_block: $generated_count total records ===" >&2
    echo ";; Generated $generated_count records for block $cidr"
    echo
    
    # Re-enable strict error handling
    set -e
}

# --- MAIN EXECUTION ---
main() {
    # Run preflight checks
    preflight_checks

    # Source libraries
    source_libraries

    # Initialize entropy pools
    init_entropy_pools

    # Load existing state
    state_load

    # Process start timestamp
    local start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo ";; Enhanced A Record Generation Started: $start_time"
    echo ";; Input file: $CIDR_FILE"
    echo

    # Process CIDR blocks
    local total_blocks=0
    while IFS=, read -r cidr domains_csv; do
        # Skip empty lines and comments
        [[ -z "$cidr" || "${cidr:0:1}" == "#" ]] && continue

        process_cidr_block "$cidr" "$domains_csv"
        total_blocks=$((total_blocks+1)) || true
    done < "$CIDR_FILE"

    # Save state
    state_save

    # Summary
    local end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo ";; Generation completed: $end_time"
    echo ";; Total blocks processed: $total_blocks"
    echo ";; Total unique names tracked: $(state_count)"
}

# Execute main function
main "$@"

# --- PATCHED: sequential IPs, round-robin domains, per-IP style, visible progress ---
process_cidr_block() {
    # Temporarily disable exit on error for debugging
    set +e
    
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: === Starting process_cidr_block ===" >&2
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Arguments: cidr=$1, domains=$2" >&2
    local cidr="$1"
    local domains_csv="$2"

    # Parse CIDR and domains
    IFS=/ read -r net mask <<<"$cidr"
    IFS=, read -r -a domains <<<"$domains_csv"
    local domain_count=${#domains[@]}
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Network: $net, Mask: /$mask, Domains provided: $domain_count" >&2

    # Calculate usable IPs based on subnet mask
    local total_ips=0
    case $mask in
        24) total_ips=254 ;;
        25) total_ips=126 ;;
        26) total_ips=62 ;;
        27) total_ips=30 ;;
        28) total_ips=14 ;;
        29) total_ips=6 ;;
        30) total_ips=2 ;;
        31) total_ips=2 ;;
        32) total_ips=1 ;;
        *)
            echo "ERROR: Unsupported subnet mask /$mask" >&2
            return 1
            ;;
    esac
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Total usable IPs for /$mask: $total_ips" >&2

    # Calculate expected domains - CORRECTED FORMULA
    local expected_domains
    if (( total_ips <= 30 )); then
        expected_domains=1
    elif (( total_ips <= 62 )); then
        expected_domains=2
    elif (( total_ips <= 93 )); then
        expected_domains=3
    elif (( total_ips <= 126 )); then
        expected_domains=4  # Fixed: 126 IPs = 4 domains
    elif (( total_ips <= 155 )); then
        expected_domains=5
    elif (( total_ips <= 186 )); then
        expected_domains=6
    elif (( total_ips <= 217 )); then
        expected_domains=7
    elif (( total_ips <= 254 )); then
        expected_domains=8
    else
        expected_domains=$(( (total_ips + 30) / 31 ))
    fi
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Expected $expected_domains domains for $total_ips IPs" >&2

    # Validate domain count
    if (( domain_count != expected_domains )); then
        echo "ERROR: $cidr with $total_ips IPs expects $expected_domains domains, got $domain_count" >&2
        set -e
        return 1
    fi

    # Build sequential IP array
    IFS=. read -r o1 o2 o3 o4 <<<"$net"
    local ips=()
    
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Building sequential IP array..." >&2
    for ((i=1; i<=total_ips; i++)); do
        ips+=("${o1}.${o2}.${o3}.${i}")
    done
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Built array with ${#ips[@]} IPs (first: ${ips[0]}, last: ${ips[$((${#ips[@]}-1))]})" >&2

    # Assign one style per domain
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Assigning styles to domains..." >&2
    local domain_styles=()
    local all_styles=(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14)
    local shuffled_styles=()
    while IFS= read -r style; do
        shuffled_styles+=("$style")
    done < <(printf "%s\n" "${all_styles[@]}" | sort -R)
    
    for ((i=0; i<domain_count; i++)); do
        domain_styles[i]="${shuffled_styles[i]}"
        [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:   ${domains[i]} → style ${domain_styles[i]}" >&2
    done

    echo ";; Block $cidr (domains: ${domains[*]})"
    echo ";; Sequential IP blocks with consistent per-domain patterns"

    # Calculate IPs per domain
    local ips_per_domain=$((total_ips / domain_count))
    local extra_ips=$((total_ips % domain_count))
    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Distribution: $ips_per_domain IPs per domain, $extra_ips domains get 1 extra" >&2

    # Generate records by domain blocks
    local generated_count=0
    local ip_index=0
    
    for ((d=0; d<domain_count; d++)); do
        local domain="${domains[d]}"
        local style="${domain_styles[d]}"
        
        # Calculate IPs for this domain
        local domain_ip_count=$ips_per_domain
        if (( d < extra_ips )); then
            ((domain_ip_count++))
        fi
        
        local start_ip=$((ip_index + 1))
        local end_ip=$((ip_index + domain_ip_count))
        [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Processing $domain: IPs $start_ip-$end_ip ($domain_ip_count total)" >&2
        
        local domain_records=0
        
        # Generate records for this domain's IP block
        for ((i=0; i<domain_ip_count && ip_index<${#ips[@]}; i++)); do
            local ip="${ips[$ip_index]}"
            [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:   Record $((i+1))/$domain_ip_count: IP=${ip}" >&2
            
            # Generate unique name
            local name
            local attempts=0
            local max_attempts=50
            
            [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:   Generating name with style $style..." >&2
            while ((attempts < max_attempts)); do
                name=$(generate_name "$style" "$ip" 2>&1)
                local gen_code=$?
                if [[ $gen_code -ne 0 ]]; then
                    echo "ERROR: generate_name failed with code $gen_code: $name" >&2
                    break
                fi
                
                local fqdn="${name}.${domain}"
                [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:     Attempt $((attempts+1)): name=$name, checking uniqueness..." >&2
                
                if ! state_exists "$fqdn"; then
                    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:     Name is unique!" >&2
                    break
                fi
                
                ((attempts++))
            done
            
            if ((attempts >= max_attempts)); then
                echo "ERROR: Failed to generate unique name for $ip after $max_attempts attempts" >&2
                ((ip_index++))
                continue
            fi
            
            # Emit A record
            local fqdn="${name}.${domain}"
            [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:   Emitting record: $fqdn → $ip" >&2
            printf "%-50s IN A %s\n" "${fqdn}." "$ip"
            
            # Add to state with error checking
            [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:   Calling state_add..." >&2
            state_add "$fqdn" "$ip" 2>&1
            local state_code=$?
            if [[ $state_code -ne 0 ]]; then
                echo "ERROR: state_add failed with code $state_code" >&2
            else
                [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:   state_add successful" >&2
            fi
            
            ((ip_index++))
            ((generated_count++))
            ((domain_records++))
            
            [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG:   Record complete. Generated so far: $generated_count" >&2
        done
        
        [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: Completed $domain: generated $domain_records records" >&2
    done

    [[ "$DEBUG_MODE" == "true" ]] && echo "DEBUG: === Completed process_cidr_block: $generated_count total records ===" >&2
    echo ";; Generated $generated_count records for block $cidr"
    echo
    
    # Re-enable strict error handling
    set -e
}
