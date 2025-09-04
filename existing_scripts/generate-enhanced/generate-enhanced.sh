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

# --- PREFLIGHT CHECKS ---
preflight_checks() {
    local errors=0

    echo "=== Running Preflight Checks ===" >&2

    # Check for required commands
    for cmd in jq openssl xxd; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "ERROR: Required command '$cmd' not found" >&2
            ((errors++))
        fi
    done

    # Check CIDR file
    if [[ ! -f "$CIDR_FILE" ]]; then
        echo "ERROR: CIDR file '$CIDR_FILE' not found" >&2
        ((errors++))
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
            ((errors++))
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
    local cidr="$1"
    local domains_csv="$2"

    # Parse CIDR and domains
    IFS=/ read -r net mask <<<"$cidr"
    IFS=, read -r -a domains <<<"$domains_csv"
    local domain_count=${#domains[@]}

    # Enforce domain count rules
    local expected
    case $mask in
        24) expected=8 ;;
        27) expected=1 ;;
        *)
            echo "ERROR: only /24 or /27 supported (got /$mask)" >&2
            return 1
            ;;
    esac

    if (( domain_count != expected )); then
        echo "ERROR: $cidr requires $expected domains, got $domain_count" >&2
        return 1
    fi

    # Calculate IP range
    IFS=. read -r o1 o2 o3 _ <<<"$net"
    local ips=()

    if [[ $mask == "24" ]]; then
        for i in {1..254}; do
            ips+=("${o1}.${o2}.${o3}.${i}")
        done
    else
        for i in {1..30}; do
            ips+=("${o1}.${o2}.${o3}.${i}")
        done
    fi

    # Shuffle IPs for non-sequential assignment
    local shuffled_ips=()
    while IFS= read -r line; do
        shuffled_ips+=("$line")
    done < <(printf '%s\n' "${ips[@]}" | sort -R)

    # Initialize style rotation
    local available_styles=(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14)
    local style_index=0
    local names_per_style=$((${#shuffled_ips[@]} / ${#available_styles[@]} + 1))
    local current_style_count=0

    # Shuffle styles for this block
    local shuffled_styles=()
    while IFS= read -r line; do
        shuffled_styles+=("$line")
    done < <(printf '%s\n' "${available_styles[@]}" | sort -R)
    local current_style="${shuffled_styles[$style_index]}"

    echo ";; Block $cidr (domains: ${domains[*]})"
    echo ";; Using randomized IP assignment and mixed naming styles"

    # Generate records
    local generated_count=0
    for ip in "${shuffled_ips[@]}"; do
        # Rotate styles to ensure variety
        if ((current_style_count >= names_per_style)) && ((style_index < ${#shuffled_styles[@]} - 1)); then
            ((style_index++))
            current_style="${shuffled_styles[$style_index]}"
            current_style_count=0
        fi

        # Generate unique name
        local name
        local attempts=0
        local max_attempts=50

        while ((attempts < max_attempts)); do
            name=$(generate_name "$current_style" "$ip")

            # Check uniqueness across all domains
            local unique=true
            for domain in "${domains[@]}"; do
                local fqdn="${name}.${domain}"
                if state_exists "$fqdn"; then
                    unique=false
                    break
                fi
            done

            if [[ "$unique" == "true" ]]; then
                break
            fi

            ((attempts++))
        done

        if ((attempts >= max_attempts)); then
            echo "ERROR: Could not generate unique name after $max_attempts attempts" >&2
            continue
        fi

        # Emit A records and track state
        for domain in "${domains[@]}"; do
            local fqdn="${name}.${domain}"
            printf "%-50s IN A %s\n" "${fqdn}." "$ip"
            state_add "$fqdn" "$ip"
        done

        ((current_style_count++))
        ((generated_count++))
    done

    echo ";; Generated $generated_count records for block $cidr"
    echo
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
        ((total_blocks++))
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
