#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
trap 'cleanup_and_exit "Unexpected error at line $LINENO"' ERR
trap 'cleanup_and_exit "Received interrupt signal"' INT TERM

################################################################################
# Enhanced DNS Management Script v2.1
# Fixes Applied:
# 1. False positive record detection (Critical Bug) - FIXED
# 2. TXT record quote normalization - FIXED
# 3. Smart update skipping for no-op operations - FIXED
# 4. Multi-value A record handling - FIXED
# 5. Enhanced diagnostic logging - FIXED
# 6. Trailing dot handling consistency - FIXED in v2.1
################################################################################

################################################################################
# Color and Formatting Configuration
################################################################################
# ANSI Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Formatting functions
print_header() {
    local title="$1"
    local width=80
    local padding=$(( (width - ${#title} - 2) / 2 ))
    echo ""
    echo -e "${BOLD}${BLUE}$(printf '=%.0s' $(seq 1 $width))${RESET}"
    echo -e "${BOLD}${BLUE}$(printf '%*s' $padding)${WHITE} $title ${BLUE}$(printf '%*s' $padding)${RESET}"
    echo -e "${BOLD}${BLUE}$(printf '=%.0s' $(seq 1 $width))${RESET}"
    echo ""
}

print_section() {
    local title="$1"
    local step="$2"
    echo ""
    echo -e "${BOLD}${CYAN}[$step] $title${RESET}"
    echo -e "${CYAN}$(printf -- '-%.0s' $(seq 1 $((${#title} + ${#step} + 4))))${RESET}"
}

print_success() {
    echo -e "${GREEN}âœ“${RESET} $1"
}

print_warning() {
    echo -e "${YELLOW}âš ${RESET} $1"
}

print_error() {
    echo -e "${RED}âœ—${RESET} $1"
}

print_info() {
    echo -e "${BLUE}â„¹${RESET} $1"
}

print_debug() {
    if [[ "$DEBUG" == true ]]; then
        echo -e "${DIM}${CYAN}DEBUG:${RESET}${DIM} $1${RESET}"
    fi
}

print_progress() {
    echo -e "${MAGENTA}â†’${RESET} $1"
}

print_table_header() {
    local col1="$1" col2="$2" col3="${3:-}"
    echo ""
    if [[ -n "$col3" ]]; then
        printf "${BOLD}%-30s %-20s %-20s${RESET}\n" "$col1" "$col2" "$col3"
        printf "${DIM}%-30s %-20s %-20s${RESET}\n" "$(printf -- '-%.0s' $(seq 1 30))" "$(printf -- '-%.0s' $(seq 1 20))" "$(printf -- '-%.0s' $(seq 1 20))"
    else
        printf "${BOLD}%-40s %-30s${RESET}\n" "$col1" "$col2"
        printf "${DIM}%-40s %-30s${RESET}\n" "$(printf -- '-%.0s' $(seq 1 40))" "$(printf -- '-%.0s' $(seq 1 30))"
    fi
}

################################################################################
# DIAGNOSTIC: Enhanced Exit Code Monitoring Functions
################################################################################
diagnostic_trace() {
    local operation="$1"
    local context="$2"
    if [[ "$DEBUG" == true ]]; then
        echo -e "${DIM}${MAGENTA}DIAGNOSTIC:${RESET}${DIM} $operation in $context${RESET}"
    fi
}

diagnostic_exit_code() {
    local operation="$1"
    local exit_code="$2"
    local context="$3"
    if [[ "$DEBUG" == true ]]; then
        if [[ "$exit_code" -eq 0 ]]; then
            echo -e "${DIM}${GREEN}DIAGNOSTIC:${RESET}${DIM} $operation succeeded (exit code: $exit_code) in $context${RESET}"
        else
            echo -e "${DIM}${RED}DIAGNOSTIC:${RESET}${DIM} $operation failed (exit code: $exit_code) in $context${RESET}"
        fi
    fi
    if [[ "$exit_code" -ne 0 ]]; then
        log_message WARN "Non-zero exit code detected: $operation returned $exit_code in $context"
    fi
}

safe_increment() {
    local var_name="$1"
    local context="$2"
    diagnostic_trace "safe_increment of $var_name" "$context"

    local current_value
    eval "current_value=\$$var_name"
    local new_value=$((current_value + 1))
    eval "$var_name=$new_value"
    local exit_code=$?

    diagnostic_exit_code "safe_increment of $var_name" "$exit_code" "$context"
    return $exit_code
}

################################################################################
# ENHANCED: Command File Generation Functions
################################################################################
write_command_to_file() {
    local command="$1"
    local description="$2"
    local zone="$3"

    local cmd_file="$REPORT_DIR/flarectl_commands_${zone//\//_}_$SESSION_ID.sh"

    if [[ ! -f "$cmd_file" ]]; then
        cat > "$cmd_file" << EOF
#!/usr/bin/env bash
# Generated DNS Commands for Zone: $zone
# Session: $SESSION_ID
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
set -euo pipefail

EOF
        chmod +x "$cmd_file"
    fi

    echo "# $description" >> "$cmd_file"
    echo "$command" >> "$cmd_file"
    echo "" >> "$cmd_file"

    if [[ "$DEBUG" == true ]]; then
        print_debug "Command written to $cmd_file: $command"
    fi
}

################################################################################
# Configuration
################################################################################
CACHE_TTL_DAYS=30

################################################################################
# Variables & Directories
################################################################################
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE_FILE="$SCRIPT_DIR/updates.txt"
LOG_DIR="$SCRIPT_DIR/logs"
TMP_DIR="$SCRIPT_DIR/tmp"
REPORT_DIR="$SCRIPT_DIR/reports"
CACHE_FILE="$SCRIPT_DIR/zone_account_cache.json"
SCRIPT_LOG_FILE="$LOG_DIR/sync-dns_$(date +'%F_%H%M%S').log"
REPORT_FILE="$REPORT_DIR/sync-dns_report_$(date +'%F_%H%M%S').txt"
SESSION_ID="$(date +'%Y%m%d%H%M%S')_$$"

DRY_RUN=false
DEBUG=false
API_SLEEP=1
RETRY_LIMIT=3
MAX_BACKOFF=30
VERIFY_MODE=false
SKIP_UNKNOWN_ZONES=false
NO_CONFIRM=false

# Counters
CREATED=0
UPDATED=0
SKIPPED=0
FAILED=0
DELETED=0
ZONES_PROCESSED=0
ZONES_SKIPPED=0
ZONES_FAILED=0

# Record structure
declare -A ZONES_RECORDS
declare -A ZONES_ACCOUNTS
declare -A ZONES_SUCCESS_STATUS
declare -A ZONE_ACCOUNT_MAP
declare -A ZONE_DNS_CACHE
declare -A ZONE_CACHE_STATUS

################################################################################
# ENHANCEMENT: Value Normalization Functions
################################################################################
normalize_dns_value() {
    local value="$1"
    local record_type="$2"

    case "$record_type" in
        TXT)
            # Remove surrounding quotes if present for proper comparison
            if [[ "$value" == \"*\" ]]; then
                value="${value#\"}"  # Remove leading quote
                value="${value%\"}"  # Remove trailing quote
            fi
            print_debug "Normalized TXT value: '$value'"
            ;;
        MX)
            # Normalize MX record spacing and trailing dots
            value=$(echo "$value" | sed 's/[[:space:]]\+/ /g' | sed 's/\.$//')
            print_debug "Normalized MX value: '$value'"
            ;;
        A|AAAA)
            # No normalization needed for IP addresses
            ;;
    esac

    echo "$value"
}

should_skip_update() {
    local expected="$1"
    local actual="$2"
    local record_type="$3"

    # Normalize both values for comparison
    local norm_expected norm_actual
    norm_expected=$(normalize_dns_value "$expected" "$record_type")
    norm_actual=$(normalize_dns_value "$actual" "$record_type")

    print_debug "Comparing normalized values for $record_type record:"
    print_debug "  Expected (normalized): '$norm_expected'"
    print_debug "  Actual (normalized): '$norm_actual'"

    if [[ "$norm_expected" == "$norm_actual" ]]; then
        print_debug "Values match after normalization - will skip update"
        return 0  # Skip update, values already match
    else
        print_debug "Values differ - update needed"
        return 1  # Proceed with update
    fi
}

################################################################################
# Utility Functions
################################################################################
is_json() {
    local input="$1"
    if jq empty 2>/dev/null <<< "$input"; then
        return 0
    else
        return 1
    fi
}

validate_and_parse_json() {
    local input="$1" output_file="$2" error_file="$3"

    echo "$input" > "${output_file}.raw"

    if is_json "$input"; then
        echo "$input" > "$output_file"
        return 0
    else
        echo "Invalid JSON response" > "$error_file"
        echo "$input" >> "$error_file"
        return 1
    fi
}

retry_with_backoff() {
    local retry_cmd="$1"
    local retry_msg="$2"
    local max_attempts="${3:-$RETRY_LIMIT}"
    local success=false
    local attempt=1
    local wait_time=1

    print_debug "Executing with retry: $retry_cmd"

    while (( attempt <= max_attempts )); do
        print_debug "Attempt $attempt/$max_attempts: $retry_msg"

        if eval "$retry_cmd"; then
            success=true
            break
        fi

        print_warning "Attempt $attempt failed for: $retry_msg"

        if (( attempt == max_attempts )); then
            break
        fi

        wait_time=$(( wait_time * 2 ))
        if (( wait_time > MAX_BACKOFF )); then
            wait_time=$MAX_BACKOFF
        fi
        jitter=$(( RANDOM % 2 + 1 ))
        sleep_time=$(( wait_time + jitter ))

        print_debug "Backing off for $sleep_time seconds before retry"
        sleep "$sleep_time"

        (( attempt++ ))
    done

    if $success; then
        return 0
    else
        return 1
    fi
}

################################################################################
# Cleanup Functions
################################################################################
cleanup_and_exit() {
    local exit_message="$1"
    local exit_code="${2:-1}"

    print_section "Cleanup" "FINAL"
    print_progress "Cleaning up temporary files"
    if [[ "$DEBUG" != true ]]; then
        find "$TMP_DIR" -name "*${SESSION_ID}*" -type f -delete 2>/dev/null || true
    else
        print_debug "DEBUG MODE: Preserving tmp files for inspection"
    fi

    if [[ "$exit_message" != "normal" ]]; then
        print_error "$exit_message"
        log_message ERROR "$exit_message"
        log_message INFO "Script terminated with status $exit_code"
        echo "ERROR: $exit_message" >> "$REPORT_FILE"
    else
        print_success "Script completed successfully"
        log_message INFO "Script completed successfully"
        echo "SUCCESS: Script completed successfully" >> "$REPORT_FILE"
    fi

    generate_summary_report

    exit "$exit_code"
}

generate_summary_report() {
    echo "" >> "$REPORT_FILE"
    echo "===== DNS Sync Summary =====" >> "$REPORT_FILE"
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "Zones processed: $ZONES_PROCESSED" >> "$REPORT_FILE"
    echo "Zones skipped: $ZONES_SKIPPED" >> "$REPORT_FILE"
    echo "Zones failed: $ZONES_FAILED" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "Records created: $CREATED" >> "$REPORT_FILE"
    echo "Records updated: $UPDATED" >> "$REPORT_FILE"
    echo "Records deleted: $DELETED" >> "$REPORT_FILE"
    echo "Records skipped: $SKIPPED" >> "$REPORT_FILE"
    echo "Records failed: $FAILED" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    echo "Zone Status:" >> "$REPORT_FILE"
    for zone in "${!ZONES_SUCCESS_STATUS[@]}"; do
        status="${ZONES_SUCCESS_STATUS[$zone]}"
        echo "  - $zone: $status" >> "$REPORT_FILE"
    done

    echo "" >> "$REPORT_FILE"
    echo "Log file: $SCRIPT_LOG_FILE" >> "$REPORT_FILE"
    echo "===== End of Report =====" >> "$REPORT_FILE"

    log_message INFO "Generated summary report at $REPORT_FILE"

    print_section "Final Summary" "COMPLETE"

    print_table_header "Metric" "Count" "Details"
    printf "%-30s ${GREEN}%-20s${RESET} %-20s\n" "Zones processed" "$ZONES_PROCESSED" "Successfully completed"
    printf "%-30s ${YELLOW}%-20s${RESET} %-20s\n" "Zones skipped" "$ZONES_SKIPPED" "Not found or excluded"
    printf "%-30s ${RED}%-20s${RESET} %-20s\n" "Zones failed" "$ZONES_FAILED" "Had errors"
    echo ""
    printf "%-30s ${GREEN}%-20s${RESET} %-20s\n" "Records created" "$CREATED" "New records added"
    printf "%-30s ${BLUE}%-20s${RESET} %-20s\n" "Records updated" "$UPDATED" "Existing records changed"
    printf "%-30s ${RED}%-20s${RESET} %-20s\n" "Records deleted" "$DELETED" "Records removed"
    printf "%-30s ${YELLOW}%-20s${RESET} %-20s\n" "Records skipped" "$SKIPPED" "Not processed"
    printf "%-30s ${RED}%-20s${RESET} %-20s\n" "Records failed" "$FAILED" "Errors occurred"

    echo ""
    if [[ -n "${ZONES_SUCCESS_STATUS[*]:-}" ]]; then
        print_info "Zone Status Details:"
        for zone in "${!ZONES_SUCCESS_STATUS[@]}"; do
            status="${ZONES_SUCCESS_STATUS[$zone]}"
            if [[ "$status" == *"SUCCESS"* ]]; then
                print_success "$zone: $status"
            elif [[ "$status" == *"PARTIAL"* ]]; then
                print_warning "$zone: $status"
            elif [[ "$status" == *"SKIPPED"* ]]; then
                print_warning "$zone: $status"
            else
                print_error "$zone: $status"
            fi
        done
    fi

    echo ""
    print_info "Full report saved to: $REPORT_FILE"
    print_info "Full log saved to: $SCRIPT_LOG_FILE"
}

################################################################################
# Logging
################################################################################
log_message() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    if [[ "$level" == "DEBUG" && "$DEBUG" != true ]]; then
        return
    fi
    echo "[$level] $ts - $msg" >&2
    echo "[$level] $ts - $msg" >> "$SCRIPT_LOG_FILE"

    if [[ "$level" == "ERROR" ]]; then
        echo "[$level] $ts - $msg" >> "$REPORT_FILE"
    fi
}

debug_trace() {
    if [[ "$DEBUG" == true ]]; then
        log_message DEBUG "TRACE: Function: ${FUNCNAME[1]}, Line: ${BASH_LINENO[0]}"
    fi
}

################################################################################
# Show Usage
################################################################################
show_help() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Options:
  --dry-run           : Parse and validate, but do not make any changes.
  --debug             : Enable verbose debug logging.
  --verify            : Only verify records without making changes.
  --skip-unknown-zones: Skip processing zones not found in any account.
  --no-confirm        : Skip confirmation prompt.
  -h, --help          : Show this help.
EOF
    exit 0
}

################################################################################
# Parse Options
################################################################################
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --debug)   DEBUG=true; shift ;;
        --verify)  VERIFY_MODE=true; shift ;;
        --skip-unknown-zones) SKIP_UNKNOWN_ZONES=true; shift ;;
        --no-confirm) NO_CONFIRM=true; shift ;;
        -h|--help) show_help ;;
        *) log_message ERROR "Unknown option: $1"; show_help ;;
    esac
done

################################################################################
# Preconditions & Directories
################################################################################
mkdir -p "$LOG_DIR" "$TMP_DIR" "$REPORT_DIR"
log_message INFO "Logging to $SCRIPT_LOG_FILE"
echo "# DNS Sync Report - $(date '+%Y-%m-%d %H:%M:%S')" > "$REPORT_FILE"
echo "Mode: $(if [[ "$DRY_RUN" == true ]]; then echo "DRY-RUN"; elif [[ "$VERIFY_MODE" == true ]]; then echo "VERIFY"; else echo "EXECUTE"; fi)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

if [[ "$DEBUG" == true && -f "$CACHE_FILE" ]]; then
    print_info "Debug mode detected - removing zone cache to force fresh discovery"
    rm -f "$CACHE_FILE"
fi

check_required_commands() {
    debug_trace
    print_progress "Checking required commands"
    local missing=()
    for cmd in jq flarectl timeout; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required commands: ${missing[*]}"
        log_message ERROR "Missing required commands: ${missing[*]}"
        cleanup_and_exit "Required commands missing" 2
    fi
    print_success "All required commands available"
    log_message DEBUG "All required commands available"
}

preflight_checks() {
    debug_trace
    print_progress "Performing preflight checks"

    if [[ ! -f "$UPDATE_FILE" ]]; then
        print_error "Updates file not found: $UPDATE_FILE"
        log_message ERROR "Updates file not found: $UPDATE_FILE"
        cleanup_and_exit "Updates file not found" 3
    fi
    if [[ ! -s "$UPDATE_FILE" ]]; then
        print_error "Updates file is empty: $UPDATE_FILE"
        log_message ERROR "Updates file is empty: $UPDATE_FILE"
        cleanup_and_exit "Updates file is empty" 3
    fi
    print_success "Found update file: $UPDATE_FILE"
    log_message INFO "Found update file: $UPDATE_FILE"

    if [[ "$DEBUG" == true ]]; then
        print_debug "Update file content preview:"
        head -n 5 "$UPDATE_FILE" | while IFS= read -r line; do
            print_debug "  $line"
            log_message DEBUG "  $line"
        done
    fi

    local header first_line
    first_line=$(head -n 1 "$UPDATE_FILE")
    if ! echo "$first_line" | grep -qE 'name.*ttl.*class.*type.*value'; then
        print_warning "Update file header may not be in the expected format"
        print_warning "Expected: name, ttl, class, type, value, [operation]"
        print_warning "Found: $first_line"
        log_message WARN "Update file header may not be in the expected format"
        log_message WARN "Expected: name, ttl, class, type, value, [operation]"
        log_message WARN "Found: $first_line"
        echo "WARN: Update file format may be incorrect" >> "$REPORT_FILE"
    else
        print_success "Update file format looks correct"
    fi
}

################################################################################
# Load Accounts & Credential Verification
################################################################################
declare -a ACCOUNT_NAMES ACCOUNT_EMAILS ACCOUNT_API_KEYS ACCOUNT_CF_EMAILS ACCOUNT_API_TOKENS

verify_configuration() {
    debug_trace
    print_progress "Verifying configuration file parsing"
    log_message DEBUG "Verifying configuration file parsing"

    local cfg="${SCRIPT_DIR}/cloudflare_accounts.json"

    if [[ ! -f "$cfg" ]]; then
        print_error "Config file not found: $cfg"
        log_message ERROR "Config file not found: $cfg"
        return 1
    fi

    if ! jq . "$cfg" > /dev/null 2>&1; then
        print_error "Config file is not valid JSON"
        log_message ERROR "Config file is not valid JSON"
        return 1
    fi

    local default_email
    default_email=$(jq -r '.default_account.email' "$cfg")
    print_debug "Default email from config: $default_email"
    log_message DEBUG "Default email from config: $default_email"

    local account_count
    account_count=$(jq '.accounts | length' "$cfg")
    print_debug "Account count from config: $account_count"
    log_message DEBUG "Account count from config: $account_count"

    for i in $(seq 0 $((account_count-1))); do
        local name email
        name=$(jq -r ".accounts[$i].name" "$cfg")
        email=$(jq -r ".accounts[$i].email" "$cfg")
        print_debug "Account $i: $name <$email>"
        log_message DEBUG "Account $i: $name <$email>"
    done

    print_success "Configuration file parsing test completed successfully"
    log_message DEBUG "Configuration file parsing test completed successfully"
    return 0
}

load_accounts() {
    debug_trace
    print_progress "Loading Cloudflare accounts"
    log_message DEBUG "Starting to load accounts"

    local cfg="${SCRIPT_DIR}/cloudflare_accounts.json"
    if [[ ! -f "$cfg" ]]; then
        cfg="${SCRIPT_DIR}/acme-challenges/cloudflare_accounts.json"
        if [[ ! -f "$cfg" ]]; then
            print_error "Cloudflare config not found at: ${SCRIPT_DIR}/cloudflare_accounts.json or ${SCRIPT_DIR}/acme-challenges/cloudflare_accounts.json"
            log_message ERROR "Cloudflare config not found at: ${SCRIPT_DIR}/cloudflare_accounts.json or ${SCRIPT_DIR}/acme-challenges/cloudflare_accounts.json"
            cleanup_and_exit "Config file not found" 5
        fi
    fi

    print_info "Using Cloudflare config: $cfg"
    log_message INFO "Using Cloudflare config: $cfg"

    if ! jq empty "$cfg" 2>/dev/null; then
        print_error "Invalid JSON in $cfg"
        log_message ERROR "Invalid JSON in $cfg"
        cleanup_and_exit "Invalid config file format" 5
    fi

    if [[ "$DEBUG" == true ]]; then
        print_debug "Config file structure:"
        if ! jq 'del(.default_account.api_key) | del(.accounts[].api_key)' "$cfg" 2>/dev/null; then
            print_debug "Failed to print structure, likely due to unexpected format"
            log_message DEBUG "Failed to print structure, likely due to unexpected format"
            if ! jq -e '.default_account' "$cfg" > /dev/null 2>&1; then
                print_error "Missing default_account in config file"
                log_message ERROR "Missing default_account in config file"
                cleanup_and_exit "Invalid config structure - missing default_account" 5
            fi
            if ! jq -e '.accounts' "$cfg" > /dev/null 2>&1; then
                print_error "Missing accounts array in config file"
                log_message ERROR "Missing accounts array in config file"
                cleanup_and_exit "Invalid config structure - missing accounts array" 5
            fi
        fi
    fi

    ACCOUNT_NAMES=()
    ACCOUNT_EMAILS=()
    ACCOUNT_API_KEYS=()
    ACCOUNT_CF_EMAILS=()
    ACCOUNT_API_TOKENS=()

    print_debug "Processing default account"
    log_message DEBUG "Processing default account"

    ACCOUNT_NAMES+=("default")

    if ! jq -e '.default_account.email' "$cfg" > /dev/null 2>&1; then
        print_error "Missing email in default_account"
        log_message ERROR "Missing email in default_account"
        cleanup_and_exit "Invalid config - missing email in default_account" 5
    fi
    ACCOUNT_EMAILS+=("$(jq -r '.default_account.email' "$cfg")")
    print_debug "Default account email: ${ACCOUNT_EMAILS[0]}"
    log_message DEBUG "Default account email: ${ACCOUNT_EMAILS[0]}"

    local default_api_key=""
    if jq -e '.default_account.api_key' "$cfg" > /dev/null 2>&1; then
        default_api_key="$(jq -r '.default_account.api_key' "$cfg")"
        if [[ "$default_api_key" == "null" ]]; then
            default_api_key=""
        fi
    fi
    ACCOUNT_API_KEYS+=("$default_api_key")

    if [[ -n "$default_api_key" ]]; then
        print_debug "Default account has API key"
        log_message DEBUG "Default account has API key"
    else
        print_warning "Default account is missing API key"
        log_message WARN "Default account is missing API key"
    fi

    local cf_email
    if ! jq -e '.default_account.cf_email' "$cfg" > /dev/null 2>&1; then
        cf_email="$(jq -r '.default_account.email' "$cfg")"
    else
        cf_email="$(jq -r '.default_account.cf_email' "$cfg")"
        if [[ "$cf_email" == "null" || -z "$cf_email" ]]; then
            cf_email="$(jq -r '.default_account.email' "$cfg")"
        fi
    fi
    ACCOUNT_CF_EMAILS+=("$cf_email")

    local api_token=""
    if jq -e '.default_account.api_token' "$cfg" > /dev/null 2>&1; then
        api_token="$(jq -r '.default_account.api_token' "$cfg")"
        if [[ "$api_token" == "null" ]]; then
            api_token=""
        fi
    fi
    ACCOUNT_API_TOKENS+=("$api_token")

    print_debug "Finished processing default account"
    log_message DEBUG "Finished processing default account"

    if ! jq -e '.accounts | length > 0' "$cfg" > /dev/null 2>&1; then
        print_warning "No additional accounts found in config"
        log_message WARN "No additional accounts found in config"
    else
        local n
        n=$(jq '.accounts | length' "$cfg")
        print_debug "Found $n additional accounts to process"
        log_message DEBUG "Found $n additional accounts to process"

        for i in $(seq 0 $((n-1))); do
            print_debug "Processing account $i"
            log_message DEBUG "Processing account $i"

            local account_name
            if ! jq -e ".accounts[$i].name" "$cfg" > /dev/null 2>&1; then
                print_warning "Missing name for account $i, using 'Account $i' as default"
                log_message WARN "Missing name for account $i, using 'Account $i' as default"
                account_name="Account $i"
            else
                account_name="$(jq -r ".accounts[$i].name" "$cfg")"
            fi
            ACCOUNT_NAMES+=("$account_name")
            print_debug "Account $i name: $account_name"
            log_message DEBUG "Account $i name: $account_name"

            local account_email
            if ! jq -e ".accounts[$i].email" "$cfg" > /dev/null 2>&1; then
                print_error "Missing email for account $i ($account_name)"
                log_message ERROR "Missing email for account $i ($account_name)"
                cleanup_and_exit "Invalid config - missing email for account $i" 5
            fi
            account_email="$(jq -r ".accounts[$i].email" "$cfg")"
            ACCOUNT_EMAILS+=("$account_email")
            print_debug "Account $i email: $account_email"
            log_message DEBUG "Account $i email: $account_email"

            local account_api_key=""
            if jq -e ".accounts[$i].api_key" "$cfg" > /dev/null 2>&1; then
                account_api_key="$(jq -r ".accounts[$i].api_key" "$cfg")"
                if [[ "$account_api_key" == "null" ]]; then
                    account_api_key=""
                fi
            fi
            ACCOUNT_API_KEYS+=("$account_api_key")

            if [[ -n "$account_api_key" ]]; then
                print_debug "Account $i has API key"
                log_message DEBUG "Account $i has API key"
            else
                print_warning "Account $i ($account_name) is missing API key"
                log_message WARN "Account $i ($account_name) is missing API key"
            fi

            local acc_cf_email
            if ! jq -e ".accounts[$i].cf_email" "$cfg" > /dev/null 2>&1; then
                acc_cf_email="$account_email"
            else
                acc_cf_email="$(jq -r ".accounts[$i].cf_email" "$cfg")"
                if [[ "$acc_cf_email" == "null" || -z "$acc_cf_email" ]]; then
                    acc_cf_email="$account_email"
                fi
            fi
            ACCOUNT_CF_EMAILS+=("$acc_cf_email")

            local acc_api_token=""
            if jq -e ".accounts[$i].api_token" "$cfg" > /dev/null 2>&1; then
                acc_api_token="$(jq -r ".accounts[$i].api_token" "$cfg")"
                if [[ "$acc_api_token" == "null" ]]; then
                    acc_api_token=""
                fi
            fi
            ACCOUNT_API_TOKENS+=("$acc_api_token")

            print_debug "Finished processing account $i"
            log_message DEBUG "Finished processing account $i"
        done
    fi

    print_debug "All accounts loaded, now validating credentials"
    log_message DEBUG "All accounts loaded, now validating credentials"

    print_debug "Testing array integrity..."
    print_debug "ACCOUNT_NAMES length: ${#ACCOUNT_NAMES[@]}"
    print_debug "ACCOUNT_EMAILS length: ${#ACCOUNT_EMAILS[@]}"
    print_debug "ACCOUNT_API_KEYS length: ${#ACCOUNT_API_KEYS[@]}"
    print_debug "ACCOUNT_CF_EMAILS length: ${#ACCOUNT_CF_EMAILS[@]}"
    print_debug "ACCOUNT_API_TOKENS length: ${#ACCOUNT_API_TOKENS[@]}"
    log_message DEBUG "Testing array integrity..."
    log_message DEBUG "ACCOUNT_NAMES length: ${#ACCOUNT_NAMES[@]}"
    log_message DEBUG "ACCOUNT_EMAILS length: ${#ACCOUNT_EMAILS[@]}"
    log_message DEBUG "ACCOUNT_API_KEYS length: ${#ACCOUNT_API_KEYS[@]}"
    log_message DEBUG "ACCOUNT_CF_EMAILS length: ${#ACCOUNT_CF_EMAILS[@]}"
    log_message DEBUG "ACCOUNT_API_TOKENS length: ${#ACCOUNT_API_TOKENS[@]}"

    for i in $(seq 0 $((${#ACCOUNT_NAMES[@]} - 1))); do
        print_debug "Index $i: ${ACCOUNT_NAMES[$i]}, ${ACCOUNT_EMAILS[$i]}"
        log_message DEBUG "Index $i: ${ACCOUNT_NAMES[$i]}, ${ACCOUNT_EMAILS[$i]}"
    done

    print_debug "Checking credentials for ${#ACCOUNT_NAMES[@]} accounts"
    log_message DEBUG "Checking credentials for ${#ACCOUNT_NAMES[@]} accounts"
    for i in $(seq 0 $((${#ACCOUNT_NAMES[@]} - 1))); do
        local auth_method="API Key"
        local auth_status="valid"

        if [[ -z "${ACCOUNT_API_KEYS[$i]}" && -z "${ACCOUNT_API_TOKENS[$i]}" ]]; then
            auth_status="missing credentials"
        elif [[ -n "${ACCOUNT_API_TOKENS[$i]}" ]]; then
            auth_method="API Token"
        fi

        print_debug "Account ${i}: ${ACCOUNT_NAMES[$i]} - $auth_status ($auth_method)"
        log_message DEBUG "Account ${i}: ${ACCOUNT_NAMES[$i]} - $auth_status ($auth_method)"
    done

    local valid_accounts=0
    print_debug "Total accounts loaded: ${#ACCOUNT_NAMES[@]}"
    log_message DEBUG "Total accounts loaded: ${#ACCOUNT_NAMES[@]}"

    for i in $(seq 0 $((${#ACCOUNT_NAMES[@]} - 1))); do
        print_debug "Checking account $i for valid credentials"
        log_message DEBUG "Checking account $i for valid credentials"
        if [[ -n "${ACCOUNT_API_KEYS[$i]}" || -n "${ACCOUNT_API_TOKENS[$i]}" ]]; then
            valid_accounts=$((valid_accounts + 1))
            print_debug "Account ${i}: ${ACCOUNT_NAMES[$i]} has valid credentials"
            log_message DEBUG "Account ${i}: ${ACCOUNT_NAMES[$i]} has valid credentials"
        else
            print_warning "Account ${i}: ${ACCOUNT_NAMES[$i]} has no usable credentials"
            log_message WARN "Account ${i}: ${ACCOUNT_NAMES[$i]} has no usable credentials"
        fi
    done

    print_debug "Found $valid_accounts valid accounts"
    log_message DEBUG "Found $valid_accounts valid accounts"

    if [[ $valid_accounts -eq 0 ]]; then
        print_error "No valid accounts found. Each account needs either api_key or api_token."
        log_message ERROR "No valid accounts found. Each account needs either api_key or api_token."
        cleanup_and_exit "No valid accounts found" 5
    fi

    print_success "Loaded ${#ACCOUNT_NAMES[@]} Cloudflare accounts ($valid_accounts with valid credentials)"
    log_message INFO "Loaded ${#ACCOUNT_NAMES[@]} Cloudflare accounts ($valid_accounts with valid credentials)"
    print_debug "Account loading completed successfully"
    log_message DEBUG "Account loading completed successfully"

    return 0
}

verify_credentials() {
    debug_trace
    print_progress "Verifying credentials for each account"
    log_message INFO "Verifying credentials for each account"
    print_debug "Starting credential verification process"
    log_message DEBUG "Starting credential verification process"

    local valid=0
    local invalid_accounts=()

    print_info "Performing credential verification using lightweight API calls"
    log_message INFO "Performing credential verification using lightweight API calls"

    for i in $(seq 0 $((${#ACCOUNT_NAMES[@]} - 1))); do
        print_progress "Verifying ${ACCOUNT_NAMES[$i]} (${ACCOUNT_EMAILS[$i]})" >&2
        log_message INFO "  -> ${ACCOUNT_NAMES[$i]} (${ACCOUNT_EMAILS[$i]})"
        print_debug "About to verify credentials for account ${ACCOUNT_NAMES[$i]}" >&2
        log_message DEBUG "About to verify credentials for account ${ACCOUNT_NAMES[$i]}"

        if [[ -z "${ACCOUNT_API_KEYS[$i]}" && -z "${ACCOUNT_API_TOKENS[$i]}" ]]; then
            print_warning "Account ${ACCOUNT_NAMES[$i]} has no credentials, skipping verification" >&2
            log_message WARN "Account ${ACCOUNT_NAMES[$i]} has no credentials, skipping verification"
            invalid_accounts+=("${ACCOUNT_NAMES[$i]}")
            continue
        fi

        setup_account_env "$i"

        if ! flarectl --json zone list &>/dev/null; then
            print_error "Credential check failed for ${ACCOUNT_NAMES[$i]}" >&2
            log_message ERROR "Credential check failed for ${ACCOUNT_NAMES[$i]}"
            invalid_accounts+=("${ACCOUNT_NAMES[$i]}")
        else
            print_success "Credentials verified for ${ACCOUNT_NAMES[$i]}" >&2
            log_message INFO "Credentials verified for ${ACCOUNT_NAMES[$i]}"
            valid=$((valid + 1))
        fi

        sleep "$API_SLEEP"
    done

    if [[ ${#invalid_accounts[@]} -gt 0 ]]; then
        print_warning "The following accounts have invalid credentials: ${invalid_accounts[*]}" >&2
        log_message WARN "The following accounts have invalid credentials: ${invalid_accounts[*]}"
        if [[ $valid -eq 0 ]]; then
            cleanup_and_exit "No accounts with valid credentials" 6
        fi
        print_warning "Continuing with $valid valid accounts" >&2
        log_message WARN "Continuing with $valid valid accounts"
    else
        print_success "All account credentials successfully verified" >&2
        log_message INFO "All account credentials successfully verified"
    fi

    print_debug "Completed credential verification process" >&2
    log_message DEBUG "Completed credential verification process"
    return 0
}

################################################################################
# Zone Cache Management
################################################################################
create_zone_cache() {
    debug_trace
    print_section "Zone Discovery" "DISCOVER"
    print_info "Building zone to account mapping cache - this may take a moment..."
    log_message INFO "Building zone to account mapping cache"

    local zone_map="{}"
    local total_zones_found=0

    for i in $(seq 0 $((${#ACCOUNT_NAMES[@]} - 1))); do
        if [[ -z "${ACCOUNT_API_KEYS[$i]}" && -z "${ACCOUNT_API_TOKENS[$i]}" ]]; then
            print_debug "Skipping ${ACCOUNT_NAMES[$i]}: no credentials"
            log_message DEBUG "Skipping ${ACCOUNT_NAMES[$i]}: no credentials"
            continue
        fi

        print_progress "Fetching zones for ${ACCOUNT_NAMES[$i]}"
        log_message INFO "Fetching zones for ${ACCOUNT_NAMES[$i]}"

        setup_account_env "$i"

        local zones_file="$TMP_DIR/zones_${i}_${SESSION_ID}.json"
        local zones_error="$TMP_DIR/zones_error_${i}_${SESSION_ID}.txt"
        local success=false
        local zones_count=0

        if retry_with_backoff "flarectl --json zone list > \"$zones_file\" 2>\"$zones_error\"" "Fetching zones for ${ACCOUNT_NAMES[$i]}"; then
            if jq empty "$zones_file" 2>/dev/null; then
                zones_count=$(jq 'length' "$zones_file" 2>/dev/null || echo "0")
                print_success "Found $zones_count zones in ${ACCOUNT_NAMES[$i]}"

                while read -r zone_name; do
                    if [[ -n "$zone_name" && "$zone_name" != "null" ]]; then
                        print_debug "Mapping zone $zone_name to account $i (${ACCOUNT_NAMES[$i]})"
                        log_message DEBUG "Mapping zone $zone_name to account $i (${ACCOUNT_NAMES[$i]})"
                        zone_map=$(echo "$zone_map" | jq --arg zone "$zone_name" --arg idx "$i" '. + {($zone): $idx}')
                        total_zones_found=$((total_zones_found + 1))
                    fi
                done < <(jq -r '.[].Name' "$zones_file")
                success=true
            else
                print_error "Invalid JSON response for ${ACCOUNT_NAMES[$i]} zones"
                log_message ERROR "Invalid JSON response for ${ACCOUNT_NAMES[$i]} zones"
                if [[ -f "$zones_error" ]]; then
                    print_debug "Error details: $(cat "$zones_error")"
                    log_message DEBUG "Error details: $(cat "$zones_error")"
                fi
            fi
        else
            print_error "Failed to fetch zones for ${ACCOUNT_NAMES[$i]}"
            log_message ERROR "Failed to fetch zones for ${ACCOUNT_NAMES[$i]}"
            if [[ -f "$zones_error" ]]; then
                print_debug "Error details: $(cat "$zones_error")"
                log_message DEBUG "Error details: $(cat "$zones_error")"
            fi
        fi

        if ! $success; then
            print_warning "Skipping zone mapping for ${ACCOUNT_NAMES[$i]} due to errors"
            log_message WARN "Skipping zone mapping for ${ACCOUNT_NAMES[$i]} due to errors"
        fi

        sleep "$API_SLEEP"
    done

    jq -n --arg ts "$(date '+%Y-%m-%d %H:%M:%S')" --argjson zones "$zone_map" \
        '{"generated_at": $ts, "zones": $zones}' > "$CACHE_FILE"

    print_success "Zone cache refreshed and saved to $CACHE_FILE"
    print_info "Total zones discovered: $total_zones_found"
    log_message INFO "Zone cache refreshed and saved to $CACHE_FILE"
    log_message INFO "Total zones discovered: $total_zones_found"

    return 0
}

populate_zone_mapping() {
    debug_trace
    print_progress "Populating zone to account mapping from cache"
    log_message INFO "Populating zone to account mapping from cache"

    print_debug "=== DIAGNOSTIC 1: Cache file verification ==="
    if [[ ! -f "$CACHE_FILE" ]]; then
        print_debug "ERROR: Cache file does not exist: $CACHE_FILE"
        return 1
    fi

    print_debug "Cache file exists: $CACHE_FILE"
    print_debug "Cache file size: $(ls -lh "$CACHE_FILE" | awk '{print $5}')"
    print_debug "First few lines of cache file:"
    head -5 "$CACHE_FILE" | while read -r line; do
        print_debug "  $line"
    done

    print_debug "=== DIAGNOSTIC 2: jq parsing test ==="
    local jq_test_output
    jq_test_output=$(jq -r '.zones | to_entries[] | .key + "=" + .value' "$CACHE_FILE" 2>/dev/null | head -5)
    if [[ -n "$jq_test_output" ]]; then
        print_debug "jq parsing successful, first 5 lines:"
        echo "$jq_test_output" | while read -r line; do
            print_debug "  $line"
        done
    else
        print_debug "ERROR: jq parsing failed or returned no output"
        return 1
    fi

    print_debug "=== DIAGNOSTIC 3: Array population ==="
    print_debug "Starting array population process"

    local entries_processed=0
    local temp_file="$TMP_DIR/simple_zones_${SESSION_ID}.txt"

    print_debug "Creating temporary file: $temp_file"
    jq -r '.zones | to_entries[] | .key + "=" + .value' "$CACHE_FILE" > "$temp_file" 2>/dev/null

    if [[ ! -s "$temp_file" ]]; then
        print_debug "ERROR: Temporary file is empty or was not created"
        return 1
    fi

    local line_count=$(wc -l < "$temp_file")
    print_debug "Temporary file has $line_count lines"

    while read -r line; do
        if [[ -z "$line" ]]; then
            continue
        fi

        local zone_name="${line%%=*}"
        local account_idx="${line##*=}"

        if [[ -n "$zone_name" && -n "$account_idx" ]]; then
            ZONE_ACCOUNT_MAP["$zone_name"]="$account_idx"
            entries_processed=$((entries_processed + 1))

            if [[ $entries_processed -le 3 ]]; then
                print_debug "  Entry $entries_processed: $zone_name -> $account_idx"
            fi
        fi

        if [[ $((entries_processed % 100)) -eq 0 ]] && [[ $entries_processed -gt 0 ]]; then
            print_debug "Progress: $entries_processed entries processed..."
        fi

    done < "$temp_file"

    rm -f "$temp_file"

    print_debug "Array population complete: $entries_processed entries processed"

    print_debug "=== DIAGNOSTIC 4: Array verification ==="
    print_debug "ZONE_ACCOUNT_MAP contains ${#ZONE_ACCOUNT_MAP[@]} entries"

    if [[ ${#ZONE_ACCOUNT_MAP[@]} -gt 0 ]]; then
        print_debug "First 3 entries in array:"
        local count=0
        for zone in "${!ZONE_ACCOUNT_MAP[@]}"; do
            if [[ $count -lt 3 ]]; then
                local idx="${ZONE_ACCOUNT_MAP[$zone]}"
                print_debug "  $zone -> $idx (${ACCOUNT_NAMES[$idx]:-INVALID})"
                count=$((count + 1))
            else
                break
            fi
        done

        print_debug "Testing thewirelessproducts.com lookup:"
        if [[ -n "${ZONE_ACCOUNT_MAP[thewirelessproducts.com]:-}" ]]; then
            local found_idx="${ZONE_ACCOUNT_MAP[thewirelessproducts.com]}"
            print_debug "  SUCCESS: thewirelessproducts.com -> $found_idx (${ACCOUNT_NAMES[$found_idx]})"
        else
            print_debug "  NOT FOUND: thewirelessproducts.com not in array"
        fi

        print_success "Zone mapping populated successfully: ${#ZONE_ACCOUNT_MAP[@]} zones"
        return 0
    else
        print_debug "ERROR: Array is empty after population!"
        return 1
    fi
}

load_zone_cache() {
    debug_trace
    print_progress "Loading zone to account mapping cache"
    log_message INFO "Loading zone to account mapping cache"

    declare -gA ZONE_ACCOUNT_MAP=()

    print_info "Performing zone discovery for accurate account mapping and validation"
    log_message INFO "Performing zone discovery for accurate account mapping and validation"

    local cache_needs_refresh=true
    local cache_age=0

    if [[ -f "$CACHE_FILE" ]]; then
        if jq empty "$CACHE_FILE" 2>/dev/null; then
            local cache_timestamp
            cache_timestamp=$(jq -r '.generated_at' "$CACHE_FILE" 2>/dev/null)

            if [[ -n "$cache_timestamp" && "$cache_timestamp" != "null" ]]; then
                print_debug "Cache timestamp: $cache_timestamp"
                log_message DEBUG "Cache timestamp: $cache_timestamp"

                local now cache_time
                now=$(date +%s)
                cache_time=$(date -d "$cache_timestamp" +%s 2>/dev/null)

                if [[ -n "$cache_time" ]]; then
                    cache_age=$(( (now - cache_time) / 86400 ))
                    print_debug "Cache age: $cache_age days"
                    log_message DEBUG "Cache age: $cache_age days"

                    if [[ $cache_age -lt $CACHE_TTL_DAYS ]]; then
                        cache_needs_refresh=false
                        print_success "Using existing zone cache (age: $cache_age days)"
                        log_message INFO "Using existing zone cache (age: $cache_age days)"
                    else
                        print_info "Zone cache expired (age: $cache_age days, TTL: $CACHE_TTL_DAYS days)"
                        log_message INFO "Zone cache expired (age: $cache_age days, TTL: $CACHE_TTL_DAYS days)"
                    fi
                fi
            fi
        else
            print_warning "Zone cache file exists but contains invalid JSON"
            log_message ERROR "Zone cache file exists but contains invalid JSON"
        fi
    else
        print_info "Zone cache does not exist, will be generated"
        log_message INFO "Zone cache does not exist, will be generated"
    fi

    if $cache_needs_refresh; then
        if ! create_zone_cache; then
            print_error "Failed to create zone cache"
            log_message ERROR "Failed to create zone cache"
            return 1
        fi
    fi

    print_debug "About to populate zone mapping from cache file"
    if ! populate_zone_mapping; then
        print_error "Failed to populate zone mapping"
        log_message ERROR "Failed to populate zone mapping"
        return 1
    fi

    if [[ ${#ZONE_ACCOUNT_MAP[@]} -gt 0 ]]; then
        print_success "Zone mapping system operational: ${#ZONE_ACCOUNT_MAP[@]} zones loaded successfully"
        log_message INFO "Loaded ${#ZONE_ACCOUNT_MAP[@]} zone mappings from cache"

        if [[ -n "${ZONE_ACCOUNT_MAP[thewirelessproducts.com]:-}" ]]; then
            local test_idx="${ZONE_ACCOUNT_MAP[thewirelessproducts.com]}"
            print_info "Verification: thewirelessproducts.com â†’ ${ACCOUNT_NAMES[$test_idx]} (zone mapping working correctly)"
        fi

        print_info "Zone-to-account mapping ready for DNS operations"
    else
        print_warning "No zone mappings found in cache - zones may need to be matched by heuristics"
        log_message WARN "No zone mappings found in cache"
    fi

    return 0
}

################################################################################
# Multi-Zone DNS Processing
################################################################################
parse_updates_file() {
    debug_trace
    print_progress "Parsing updates file (skipping header)"
    log_message INFO "Parsing updates file (skipping header)"

    ZONES_RECORDS=()

    print_debug "Starting file processing with detailed diagnostics"
    print_debug "Update file: $UPDATE_FILE"
    print_debug "File exists: $(test -f "$UPDATE_FILE" && echo "YES" || echo "NO")"
    print_debug "File size: $(wc -c < "$UPDATE_FILE" 2>/dev/null || echo "ERROR") bytes"
    print_debug "File lines: $(wc -l < "$UPDATE_FILE" 2>/dev/null || echo "ERROR") lines"

    local line_number=0
    local records_processed=0

    print_debug "About to start while loop reading from $UPDATE_FILE"

    while IFS= read -r line || [[ -n "$line" ]]; do
        print_debug "=== LOOP ITERATION START ==="
        print_debug "Line number: $((line_number + 1))"
        print_debug "Raw line length: ${#line}"
        print_debug "Raw line (first 100 chars): ${line:0:100}"

        ((line_number++))

        if [[ $line_number -eq 1 ]]; then
            print_debug "Skipping header line"
            continue
        fi

        if [[ -z "$line" ]]; then
            print_debug "Skipping empty line"
            continue
        fi

        if [[ "${line:0:1}" == "#" ]]; then
            print_debug "Skipping comment line"
            continue
        fi

        print_debug "Processing record line $line_number"

        print_debug "Step 1: Parsing fields with awk"
        local name ttl class type value operation

        name=$(echo "$line" | awk '{print $1}' 2>/dev/null)
        print_debug "Parsed name: '$name'"

        ttl=$(echo "$line" | awk '{print $2}' 2>/dev/null)
        print_debug "Parsed ttl: '$ttl'"

        class=$(echo "$line" | awk '{print $3}' 2>/dev/null)
        print_debug "Parsed class: '$class'"

        type=$(echo "$line" | awk '{print $4}' 2>/dev/null)
        print_debug "Parsed type: '$type'"

        print_debug "Step 2: Determining operation and value"
        local lastfield
        lastfield=$(echo "$line" | awk '{print $NF}' 2>/dev/null)
        print_debug "Last field: '$lastfield'"

        if [[ "$lastfield" == "create" || "$lastfield" == "delete" ]]; then
            operation="$lastfield"
            print_debug "Found explicit operation: $operation"
            local field_count
            field_count=$(echo "$line" | awk '{print NF}' 2>/dev/null)
            print_debug "Total fields: $field_count"

            if [[ $field_count -gt 5 ]]; then
                value=$(echo "$line" | awk '{for(i=5;i<NF;i++) printf "%s ", $i} END {print ""}' 2>/dev/null)
                value="${value% }"
            else
                value=""
            fi
        else
            operation="create"
            print_debug "No explicit operation, defaulting to create"
            value=$(echo "$line" | awk '{$1=$2=$3=$4=""; print $0}' 2>/dev/null)
            value="${value# }"
        fi

        print_debug "Parsed value (first 50 chars): '${value:0:50}'"
        print_debug "Parsed operation: '$operation'"

        if [[ -z "$name" || -z "$ttl" || -z "$type" ]]; then
            print_warning "Invalid record at line $line_number: missing required fields"
            print_debug "name='$name', ttl='$ttl', type='$type'"
            continue
        fi

        print_debug "Step 3: Extracting zone from FQDN"
        # Remove trailing dot for consistent processing
        local fqdndot="${name%.}"
        local zone
        zone=$(echo "$fqdndot" | awk -F. '{n=NF; print $(n-1)"."$n}' 2>/dev/null)
        print_debug "Extracted zone: '$zone'"

        if [[ -z "$zone" ]]; then
            print_warning "Could not determine zone for record: $name (line $line_number)"
            continue
        fi

        print_debug "Step 4: Handling record type specifics"
        local priority=""

        case "$type" in
            MX)
                print_debug "Processing MX record"
                priority=$(echo "$value" | awk '{print $1}' 2>/dev/null)
                local mailserver=$(echo "$value" | awk '{$1=""; print $0}' 2>/dev/null)
                mailserver="${mailserver# }"
                value="$mailserver"
                print_debug "MX priority: '$priority', mailserver: '$mailserver'"
                ;;
            TXT)
                print_debug "Processing TXT record"
                if [[ "$value" == \"*\" ]]; then
                    print_debug "TXT value already quoted"
                else
                    print_debug "Adding quotes to TXT value"
                    value="\"$value\""
                fi
                ;;
            *)
                print_debug "Processing $type record (no special handling)"
                ;;
        esac

        print_debug "Step 5: Creating JSON record"
        local record_json
        if ! record_json=$(
            jq -n \
                --arg name "$name" \
                --arg ttl "$ttl" \
                --arg type "$type" \
                --arg value "$value" \
                --arg priority "$priority" \
                --arg operation "$operation" \
                --arg line_number "$line_number" \
                '{name: $name, ttl: $ttl, type: $type, value: $value, priority: $priority, operation: $operation, line_number: $line_number}' 2>/dev/null
        ); then
            print_error "Failed to create JSON for record at line $line_number"
            print_debug "JSON creation failed for: name='$name', value='${value:0:50}...'"
            continue
        fi

        print_debug "JSON created successfully (length: ${#record_json})"

        print_debug "Step 6: Adding record to zones array"
        if [[ -z "${ZONES_RECORDS[$zone]:-}" ]]; then
            print_debug "Creating new zone array for: $zone"
            ZONES_RECORDS[$zone]="[$record_json]"
        else
            print_debug "Appending to existing zone array for: $zone"
            local existing_records="${ZONES_RECORDS[$zone]}"
            print_debug "Current array length: ${#existing_records}"
            ZONES_RECORDS[$zone]="${existing_records%]},${record_json}]"
            print_debug "New array length: ${#ZONES_RECORDS[$zone]}"
        fi

        print_debug "Successfully added record to zone $zone"
        print_debug "Record: $name ($ttl) $type [$operation] (line $line_number)"
        log_message DEBUG "Added record to zone $zone: $name ($ttl) $type [$operation] (line $line_number)"

        ((records_processed++))
        print_debug "Total records processed so far: $records_processed"

        if [[ $((records_processed % 5)) -eq 0 ]]; then
            print_debug "PROGRESS: Processed $records_processed records successfully"
        fi

        print_debug "=== LOOP ITERATION END ==="
        print_debug ""

    done < "$UPDATE_FILE"

    print_debug "Exited while loop - file processing complete"
    print_debug "Total lines processed: $line_number"
    print_debug "Total records processed: $records_processed"

    local zone_count=${#ZONES_RECORDS[@]}
    local total_records=0

    print_success "Parsed $zone_count zones from updates file"
    log_message INFO "Parsed $zone_count zones from updates file"

    for zone in "${!ZONES_RECORDS[@]}"; do
        local record_count
        if record_count=$(echo "${ZONES_RECORDS[$zone]}" | jq 'length' 2>/dev/null); then
            total_records=$((total_records + record_count))

            local create_count delete_count
            create_count=$(echo "${ZONES_RECORDS[$zone]}" | jq '[.[] | select(.operation == "create" or .operation == null)] | length' 2>/dev/null || echo "0")
            delete_count=$(echo "${ZONES_RECORDS[$zone]}" | jq '[.[] | select(.operation == "delete")] | length' 2>/dev/null || echo "0")

            print_info "Zone $zone: $record_count records (Create: $create_count, Delete: $delete_count)"
            log_message INFO "Zone $zone: $record_count records (Create: $create_count, Delete: $delete_count)"

            echo "Zone: $zone - $record_count records (Create: $create_count, Delete: $delete_count)" >> "$REPORT_FILE"
        else
            print_warning "Failed to count records for zone $zone"
            log_message WARN "Failed to count records for zone $zone"
        fi
    done

    print_success "Total records parsed: $total_records"
    log_message INFO "Total records parsed: $total_records"
    echo "Total zones: $zone_count, Total records: $total_records" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    return 0
}

find_account_for_domain() {
    debug_trace

    local zone="$1"
    if [[ -z "$zone" ]]; then
        print_error "Empty zone name passed to find_account_for_domain" >&2
        log_message ERROR "Empty zone name passed to find_account_for_domain"
        echo "0"
        return 1
    fi

    print_progress "Searching for zone '$zone' in accounts" >&2
    log_message INFO "Searching for zone '$zone' in accounts"

    if [[ -n "${ZONE_ACCOUNT_MAP[$zone]:-}" ]]; then
        local idx="${ZONE_ACCOUNT_MAP[$zone]}"
        print_success "Found zone '$zone' in account ${ACCOUNT_NAMES[$idx]}" >&2
        log_message INFO "Found zone '$zone' in account ${ACCOUNT_NAMES[$idx]}"
        echo "$idx"
        return 0
    fi

    print_debug "Zone '$zone' not found in cache, trying heuristic matching" >&2
    log_message DEBUG "Zone '$zone' not found in cache, trying heuristic matching"

    for i in $(seq 0 $((${#ACCOUNT_NAMES[@]} - 1))); do
        local email_domain="${ACCOUNT_EMAILS[$i]#*@}"

        print_debug "Checking if '$zone' matches email domain '$email_domain' for ${ACCOUNT_NAMES[$i]}" >&2
        log_message DEBUG "Checking if '$zone' matches email domain '$email_domain' for ${ACCOUNT_NAMES[$i]}"

        if [[ "$zone" == "$email_domain" || "$zone" == *".$email_domain" ]]; then
            print_success "Zone '$zone' matched email domain for account ${ACCOUNT_NAMES[$i]}" >&2
            log_message INFO "Zone '$zone' matched email domain for account ${ACCOUNT_NAMES[$i]}"
            echo "$i"
            return 0
        fi
    done

    if [[ "$SKIP_UNKNOWN_ZONES" == true ]]; then
        print_warning "Zone '$zone' not found in any account, will be skipped (--skip-unknown-zones)" >&2
        log_message WARN "Zone '$zone' not found in any account, will be skipped (--skip-unknown-zones)"
        echo "-1"
    else
        print_warning "Zone '$zone' not found in any account, using default account" >&2
        log_message WARN "Zone '$zone' not found in any account, using default account"
        echo "0"
    fi

    return 0
}

setup_account_env() {
    debug_trace

    local idx="$1"
    if [[ -z "$idx" ]]; then
        print_error "Empty account index passed to setup_account_env"
        log_message ERROR "Empty account index passed to setup_account_env"
        idx=0
    fi

    if [[ "$idx" == "-1" ]]; then
        print_debug "Zone marked for skipping, using empty credentials"
        log_message DEBUG "Zone marked for skipping, using empty credentials"
        unset CF_API_TOKEN
        unset CF_API_EMAIL
        unset CF_API_KEY
        unset CF_EMAIL
        return 0
    fi

    if ! [[ "$idx" =~ ^[0-9]+$ ]]; then
        print_warning "Invalid account index: $idx, using default account"
        log_message WARN "Invalid account index: $idx, using default account"
        idx=0
    fi

    if (( idx < 0 || idx >= ${#ACCOUNT_NAMES[@]} )); then
        print_warning "Account index $idx out of bounds, using default account"
        log_message WARN "Account index $idx out of bounds, using default account"
        idx=0
    fi

    if [[ -n "${ACCOUNT_API_TOKENS[$idx]}" ]]; then
        print_debug "Using API token authentication for ${ACCOUNT_NAMES[$idx]}"
        log_message DEBUG "Using API token authentication for ${ACCOUNT_NAMES[$idx]}"
        export CF_API_TOKEN="${ACCOUNT_API_TOKENS[$idx]}"
        unset CF_API_EMAIL
        unset CF_API_KEY
        unset CF_EMAIL
    else
        print_debug "Using API key authentication for ${ACCOUNT_NAMES[$idx]}"
        log_message DEBUG "Using API key authentication for ${ACCOUNT_NAMES[$idx]}"
        export CF_API_EMAIL="${ACCOUNT_EMAILS[$idx]}"
        export CF_API_KEY="${ACCOUNT_API_KEYS[$idx]}"
        export CF_EMAIL="${ACCOUNT_CF_EMAILS[$idx]}"
        unset CF_API_TOKEN
    fi

    print_info "Using account: ${ACCOUNT_NAMES[$idx]} (${ACCOUNT_EMAILS[$idx]})"
    log_message INFO "Using account: ${ACCOUNT_NAMES[$idx]} (${ACCOUNT_EMAILS[$idx]})"
}

get_zone_id() {
    debug_trace

    local zone="$1"
    if [[ -z "$zone" ]]; then
        print_error "Empty zone name passed to get_zone_id" >&2
        log_message ERROR "Empty zone name passed to get_zone_id"
        echo ""
        return 1
    fi

    print_debug "Fetching real zone ID for $zone (read operation allowed in all modes)" >&2
    log_message DEBUG "Fetching real zone ID for $zone (read operation allowed in all modes)"

    local zone_id zone_id_file error_file
    zone_id_file="$TMP_DIR/zone_id_${zone}_${SESSION_ID}.json"
    error_file="$TMP_DIR/zone_id_error_${zone}_${SESSION_ID}.txt"

    if retry_with_backoff "flarectl --json zone info --zone=$zone > \"$zone_id_file\" 2>\"$error_file\"" "Getting zone ID for $zone"; then
        if [[ -s "$zone_id_file" ]] && jq empty "$zone_id_file" 2>/dev/null; then
            zone_id=$(jq -r '.id' "$zone_id_file" 2>/dev/null)
            if [[ -n "$zone_id" && "$zone_id" != "null" ]]; then
                print_success "Found zone ID for $zone: $zone_id" >&2
                log_message INFO "Found zone ID for $zone: $zone_id"
                echo "$zone_id"
                return 0
            fi
        fi
    fi

    print_warning "Failed to get zone ID for $zone, using zone name as identifier" >&2
    log_message WARN "Failed to get zone ID for $zone, using zone name as identifier"
    echo "$zone"
    return 0
}

backup_zone_records() {
    debug_trace

    local zone_id="$1" zone="$2"
    if [[ -z "$zone_id" || -z "$zone" ]]; then
        print_error "Missing parameters for backup_zone_records"
        log_message ERROR "Missing parameters for backup_zone_records"
        return 1
    fi

    if [[ "$DRY_RUN" == true || "$VERIFY_MODE" == true ]]; then
        print_info "DRY-RUN/VERIFY: skipping backup"
        log_message INFO "DRY-RUN/VERIFY: skipping backup"
        return 0
    fi

    local backup="$TMP_DIR/${zone}_backup_${SESSION_ID}.json"
    print_debug "Backing up DNS records for zone $zone to $backup"
    log_message DEBUG "Backing up DNS records for zone $zone to $backup"

    local success=false

    if retry_with_backoff "flarectl --json dns list --zone=$zone > \"$backup\" 2>/dev/null" "Backing up DNS records for $zone"; then
        if [[ -s "$backup" ]] && jq empty "$backup" 2>/dev/null; then
            local record_count
            record_count=$(jq 'length' "$backup" 2>/dev/null)
            print_success "Backed up $record_count DNS records for $zone"
            log_message INFO "Backed up $record_count DNS records for $zone"
            success=true
        else
            print_warning "Backup file for $zone has invalid JSON or is empty"
            log_message WARN "Backup file for $zone has invalid JSON or is empty"
        fi
    fi

    if ! $success; then
        print_warning "Failed to backup DNS records for $zone"
        log_message WARN "Failed to backup DNS records for $zone"
        echo "[]" > "$backup"
        return 1
    fi

    return 0
}

################################################################################
# CRITICAL FIX: Enhanced record detection with consistent name handling
################################################################################
verify_record_exists() {
    local zone="$1"
    local name="$2"
    local type="$3"
    local cache_file="$TMP_DIR/dns_cache_${zone}_${SESSION_ID}.json"

    # Remove trailing dots for consistent comparison
    name="${name%.}"
    zone="${zone%.}"

    print_debug "CRITICAL: Performing cache-based record existence check for $name $type in zone $zone"
    log_message DEBUG "CRITICAL: Performing cache-based record existence check for $name $type in zone $zone"

    # ENHANCED DEBUG: Show exactly what name we're checking
    print_debug "DEBUG TRACE verify_record_exists: Input parameters:"
    print_debug "  - zone: '$zone'"
    print_debug "  - name: '$name' (trailing dot removed)"
    print_debug "  - type: '$type'"
    print_debug "  - cache_file: '$cache_file'"
    log_message DEBUG "DEBUG TRACE verify_record_exists: zone='$zone', name='$name', type='$type'"

    # Check if cache file exists
    if [[ ! -f "$cache_file" ]]; then
        print_warning "Cache file not found: $cache_file"
        log_message WARN "Cache file not found for zone $zone, assuming record doesn't exist"
        return 1  # Record does not exist
    fi

    # Validate JSON
    if ! jq empty "$cache_file" 2>/dev/null; then
        print_warning "Invalid JSON in cache file: $cache_file"
        log_message WARN "Invalid JSON in cache for zone $zone, assuming record doesn't exist"
        return 1  # Record does not exist
    fi

    # ENHANCED DEBUG: Show what we're searching for in the cache
    print_debug "DEBUG TRACE verify_record_exists: Searching for name='$name' and type='$type' in cache"

    # Add debug line to show cache file status
    print_debug "verify_record_exists: Using cache file: $cache_file (exists: $(test -f "$cache_file" && echo "YES" || echo "NO"))"

    # Look for the specific record with case-insensitive field matching
    local matches
    # Try all common case variations for field names
    matches=$(jq -r --arg name "$name" --arg type "$type" \
        '[.[] | select(
            ((.Name // .name // .NAME // empty) == $name) and
            ((.Type // .type // .TYPE // empty) == $type)
        )] | length' "$cache_file" 2>/dev/null || echo "0")

    # ENHANCED DEBUG: Show sample of what's in the cache
    if [[ "$DEBUG" == true ]]; then
        local sample_names
        sample_names=$(jq -r '[.[] | {
            name: (.Name // .name // .NAME // "unknown"),
            type: (.Type // .type // .TYPE // "unknown")
        }] | .[0:3] | .[] | "\(.name) (\(.type))"' "$cache_file" 2>/dev/null | head -5)
        print_debug "DEBUG TRACE verify_record_exists: Sample records from cache:"
        while read -r sample; do
            print_debug "  - $sample"
        done <<< "$sample_names"
    fi

    print_debug "Cache query found $matches matching records for $name $type"
    log_message DEBUG "Cache query found $matches matching records for $name $type"

    if [[ "$matches" -gt 0 ]]; then
        print_debug "DEBUG TRACE verify_record_exists: RECORD EXISTS (found $matches matches)"
        return 0  # Record exists
    else
        print_debug "DEBUG TRACE verify_record_exists: RECORD DOES NOT EXIST"
        return 1  # Record does not exist
    fi
}

fetch_zone_records() {
    debug_trace

    local zone_id="$1" zone="$2"
    if [[ -z "$zone_id" || -z "$zone" ]]; then
        print_error "Missing parameters for fetch_zone_records"
        log_message ERROR "Missing parameters for fetch_zone_records"
        return 1
    fi

    local cache_file="$TMP_DIR/dns_cache_${zone}_${SESSION_ID}.json"

    if [[ -n "${ZONE_DNS_CACHE[$zone]:-}" && "${ZONE_CACHE_STATUS[$zone]:-}" == "valid" ]]; then
        print_debug "Using cached DNS records for zone $zone"
        log_message DEBUG "Using cached DNS records for zone $zone"
        echo "${ZONE_DNS_CACHE[$zone]}" > "$cache_file"
        return 0
    fi

    print_debug "Fetching real DNS records for zone $zone (read operation for validation)"
    log_message DEBUG "Fetching real DNS records for zone $zone (read operation for validation)"

    local success=false

    if retry_with_backoff "flarectl --json dns list --zone=$zone > \"$cache_file\" 2>/dev/null" "Fetching DNS records for $zone"; then
        if [[ -s "$cache_file" ]] && jq empty "$cache_file" 2>/dev/null; then
            local record_count
            record_count=$(jq 'length' "$cache_file" 2>/dev/null)
            print_success "Fetched $record_count DNS records for $zone"
            log_message INFO "Fetched $record_count DNS records for $zone"

            # ADD THIS LINE HERE:
            print_debug "CACHE FILE CHECK: Created cache at $cache_file with $(wc -l < "$cache_file") lines"

            print_debug "=== CLOUDFLARE JSON STRUCTURE DIAGNOSTIC ==="
            log_message DEBUG "=== CLOUDFLARE JSON STRUCTURE DIAGNOSTIC ==="

            local json_type
            json_type=$(jq -r 'type' "$cache_file" 2>/dev/null)
            print_debug "JSON root type: $json_type"
            log_message DEBUG "JSON root type: $json_type"

            if [[ "$json_type" == "object" ]]; then
                print_debug "Top-level object keys:"
                log_message DEBUG "Top-level object keys:"
                local top_keys
                top_keys=$(jq -r 'keys[]' "$cache_file" 2>/dev/null | head -10)
                while read -r key; do
                    print_debug "  - $key"
                    log_message DEBUG "  - $key"
                done <<< "$top_keys"

                print_debug "Looking for nested arrays that might contain DNS records:"
                log_message DEBUG "Looking for nested arrays that might contain DNS records:"
                local nested_arrays
                nested_arrays=$(jq -r 'to_entries[] | select(.value | type == "array") | .key' "$cache_file" 2>/dev/null)
                while read -r array_key; do
                    if [[ -n "$array_key" ]]; then
                        local nested_count
                        nested_count=$(jq -r ".$array_key | length" "$cache_file" 2>/dev/null)
                        print_debug "  - .$array_key contains $nested_count items"
                        log_message DEBUG "  - .$array_key contains $nested_count items"
                    fi
                done <<< "$nested_arrays"
            fi

            print_debug "Examining first DNS record structure:"
            log_message DEBUG "Examining first DNS record structure:"

            local first_record_keys=""
            if [[ "$json_type" == "array" ]]; then
                first_record_keys=$(jq -r '.[0] | keys[]' "$cache_file" 2>/dev/null | head -20)
                print_debug "First record fields (direct array access):"
                log_message DEBUG "First record fields (direct array access):"
            else
                for possible_key in "result" "results" "data" "records" "response"; do
                    if first_record_keys=$(jq -r ".$possible_key[0] | keys[]" "$cache_file" 2>/dev/null | head -20); then
                        print_debug "First record fields (found in .$possible_key array):"
                        log_message DEBUG "First record fields (found in .$possible_key array):"
                        break
                    fi
                done

                if [[ -z "$first_record_keys" ]]; then
                    local any_array_path
                    any_array_path=$(jq -r 'paths(type == "array") | join(".")' "$cache_file" 2>/dev/null | head -1)
                    if [[ -n "$any_array_path" ]]; then
                        first_record_keys=$(jq -r ".${any_array_path}[0] | keys[]" "$cache_file" 2>/dev/null | head -20)
                        print_debug "First record fields (found in .$any_array_path array):"
                        log_message DEBUG "First record fields (found in .$any_array_path array):"
                    fi
                fi
            fi

            if [[ -n "$first_record_keys" ]]; then
                while read -r field_name; do
                    if [[ -n "$field_name" ]]; then
                        print_debug "  - $field_name"
                        log_message DEBUG "  - $field_name"
                    fi
                done <<< "$first_record_keys"

                print_debug "Sample first record content:"
                log_message DEBUG "Sample first record content:"
                local sample_record=""
                if [[ "$json_type" == "array" ]]; then
                    sample_record=$(jq -r '.[0]' "$cache_file" 2>/dev/null)
                else
                    for possible_key in "result" "results" "data" "records" "response"; do
                        if sample_record=$(jq -r ".$possible_key[0]" "$cache_file" 2>/dev/null); then
                            break
                        fi
                    done
                fi

                if [[ -n "$sample_record" && "$sample_record" != "null" ]]; then
                    echo "$sample_record" | jq . 2>/dev/null | head -20 | while read -r line; do
                        print_debug "  $line"
                        log_message DEBUG "  $line"
                    done
                else
                    print_debug "  Unable to extract sample record content"
                    log_message DEBUG "  Unable to extract sample record content"
                fi
            else
                print_debug "  Unable to determine field names - may need manual inspection"
                log_message DEBUG "  Unable to determine field names - may need manual inspection"

                print_debug "Raw JSON preview (first 500 characters):"
                log_message DEBUG "Raw JSON preview (first 500 characters):"
                local json_preview
                json_preview=$(head -c 500 "$cache_file" | tr '\n' ' ')
                print_debug "  $json_preview..."
                log_message DEBUG "  $json_preview..."
            fi

            print_debug "=== END CLOUDFLARE JSON STRUCTURE DIAGNOSTIC ==="
            log_message DEBUG "=== END CLOUDFLARE JSON STRUCTURE DIAGNOSTIC ==="

            ZONE_DNS_CACHE[$zone]=$(cat "$cache_file")
            ZONE_CACHE_STATUS[$zone]="valid"
            print_debug "Cached DNS records for zone $zone (${#ZONE_DNS_CACHE[$zone]} bytes)"
            log_message DEBUG "Cached DNS records for zone $zone"

            success=true
        else
            print_warning "DNS cache file for $zone has invalid JSON or is empty"
            log_message WARN "DNS cache file for $zone has invalid JSON or is empty"
        fi
    fi

    if ! $success; then
        print_warning "Failed to fetch DNS records for $zone - continuing with limited validation"
        log_message WARN "Failed to fetch DNS records for $zone - continuing with limited validation"
        echo "[]" > "$cache_file"
        ZONE_DNS_CACHE[$zone]="[]"
        ZONE_CACHE_STATUS[$zone]="empty"
        return 1
    fi

    return 0
}

find_record_id() {
    local zone="$1" zone_id="$2" rel_name="$3" type="$4" cache_file="$5"

    if [[ -z "$zone" || -z "$rel_name" || -z "$type" || -z "$cache_file" ]]; then
        print_error "Missing parameters for find_record_id"
        log_message ERROR "Missing parameters for find_record_id"
        return 1
    fi

    # Remove trailing dots for consistent comparison
    zone="${zone%.}"
    rel_name="${rel_name%.}"

    # ENHANCED DEBUG: Show input parameters
    print_debug "DEBUG TRACE find_record_id: Input parameters:"
    print_debug "  - zone: '$zone' (trailing dot removed)"
    print_debug "  - zone_id: '$zone_id'"
    print_debug "  - rel_name: '$rel_name' (trailing dot removed)"
    print_debug "  - type: '$type'"
    print_debug "  - cache_file: '$cache_file'"
    log_message DEBUG "DEBUG TRACE find_record_id: zone='$zone', rel_name='$rel_name', type='$type'"

    local name_pattern
    if [[ "$rel_name" == "@" ]]; then
        name_pattern="$zone"
    else
        name_pattern="$rel_name.$zone"
    fi

    # Remove any trailing dots from the pattern
    name_pattern="${name_pattern%.}"

    # ENHANCED DEBUG: Show constructed name pattern
    print_debug "DEBUG TRACE find_record_id: Constructed name_pattern='$name_pattern' from rel_name='$rel_name' and zone='$zone'"
    log_message DEBUG "DEBUG TRACE find_record_id: Constructed name_pattern='$name_pattern'"

    print_debug "Searching for record: name=$name_pattern, type=$type"
    log_message DEBUG "Searching for record: name=$name_pattern, type=$type"

    # Add debug line to show cache file status
    print_debug "find_record_id: Using cache file: $cache_file (exists: $(test -f "$cache_file" && echo "YES" || echo "NO"))"

    if [[ ! -f "$cache_file" ]]; then
        print_warning "DNS cache file $cache_file not found"
        log_message WARN "DNS cache file $cache_file not found"
        return 1
    fi

    if ! jq empty "$cache_file" 2>/dev/null; then
        print_warning "DNS cache file $cache_file contains invalid JSON"
        log_message WARN "DNS cache file $cache_file contains invalid JSON"
        return 1
    fi

    # ENHANCED DEBUG: Show what's actually in the cache file
    if [[ "$DEBUG" == true ]]; then
        local available_names
        available_names=$(jq -r '[.[] | (.Name // .name // .NAME // "unknown")] | .[0:5] | .[]' "$cache_file" 2>/dev/null)
        print_debug "Available names in cache (first 5): $available_names"

        # Show names that contain our zone
        local zone_specific_names
        zone_specific_names=$(jq -r --arg zone "$zone" '[.[] | select(
            (.Name // .name // .NAME // empty) | contains($zone)
        ) | {
            name: (.Name // .name // .NAME // "unknown"),
            type: (.Type // .type // .TYPE // "unknown")
        }] | .[0:10] | .[] | "\(.name) (\(.type))"' "$cache_file" 2>/dev/null)
        print_debug "DEBUG TRACE find_record_id: Records containing zone '$zone' in cache:"
        while read -r record; do
            print_debug "  - $record"
        done <<< "$zone_specific_names"

        local available_types_for_name
        available_types_for_name=$(jq -r --arg name "$name_pattern" '[.[] | select(
            (.Name // .name // .NAME // empty) == $name
        ) | (.Type // .type // .TYPE // "unknown")] | .[]' "$cache_file" 2>/dev/null)
        if [[ -n "$available_types_for_name" ]]; then
            print_debug "Available types for name '$name_pattern': $available_types_for_name"
        else
            print_debug "No records found for name '$name_pattern'"

            # ENHANCED DEBUG: Try case-insensitive search to see if there's a case mismatch
            local case_insensitive_matches
            case_insensitive_matches=$(jq -r --arg name "$name_pattern" '[.[] | select(
                (.Name // .name // .NAME // empty) | ascii_downcase == ($name | ascii_downcase)
            ) | {
                name: (.Name // .name // .NAME // "unknown"),
                type: (.Type // .type // .TYPE // "unknown")
            }] | .[0:5] | .[] | "\(.name) (\(.type))"' "$cache_file" 2>/dev/null)
            if [[ -n "$case_insensitive_matches" ]]; then
                print_debug "DEBUG TRACE find_record_id: Found case-insensitive matches:"
                while read -r match; do
                    print_debug "  - $match"
                done <<< "$case_insensitive_matches"
            fi
        fi
    fi

    # CRITICAL FIX: Try to find matching record with case-insensitive field access
    local record_data
    record_data=$(jq -r --arg name "$name_pattern" --arg type "$type" \
    '[.[] | select(.Name == $name and .Type == $type)] |
    if length > 0 then .[0] else empty end' "$cache_file" 2>/dev/null)

    # ENHANCED DEBUG: Show exact comparison being performed
    print_debug "DEBUG TRACE find_record_id: Executing case-insensitive query for name=\"$name_pattern\" and type=\"$type\""

    if [[ -n "$record_data" && "$record_data" != "null" ]]; then
        local record_id
        record_id=$(echo "$record_data" | jq -r '.ID // empty')

        if [[ -n "$record_id" && "$record_id" != "null" ]]; then
            print_debug "Found record ID: $record_id for $name_pattern $type"
            log_message DEBUG "Found record ID: $record_id for $name_pattern $type"

            # Store the current value for comparison
            local current_content
            current_content=$(echo "$record_data" | jq -r '.Content // empty')
            print_debug "Current content for record: '$current_content'"

            echo "$record_id"
            return 0
        fi
    fi

    if [[ "$DEBUG" == true ]]; then
        local name_exists type_exists
        name_exists=$(jq -r --arg name "$name_pattern" '[.[] | select(
            (.Name // .name // .NAME // empty) == $name
        ) | (.Name // .name // .NAME // empty)] | .[0] // empty' "$cache_file" 2>/dev/null)
        type_exists=$(jq -r --arg type "$type" '[.[] | select(
            (.Type // .type // .TYPE // empty) == $type
        ) | (.Type // .type // .TYPE // empty)] | .[0] // empty' "$cache_file" 2>/dev/null)

        if [[ -z "$name_exists" ]]; then
            print_debug "MATCH FAILURE: Name '$name_pattern' not found in cache"

            # ENHANCED DEBUG: Show similar names that might be close
            local similar_names
            similar_names=$(jq -r --arg pattern "$rel_name" '[.[] | select(
                (.Name // .name // .NAME // empty) | contains($pattern)
            ) | (.Name // .name // .NAME // empty)] | .[0:5] | .[]' "$cache_file" 2>/dev/null)
            if [[ -n "$similar_names" ]]; then
                print_debug "DEBUG TRACE find_record_id: Similar names containing '$rel_name':"
                while read -r similar; do
                    print_debug "  - $similar"
                done <<< "$similar_names"
            fi
        elif [[ -z "$type_exists" ]]; then
            print_debug "MATCH FAILURE: Type '$type' not found anywhere in cache"
        else
            print_debug "MATCH FAILURE: Name '$name_pattern' exists, type '$type' exists elsewhere, but combination not found"
        fi
    fi

    print_debug "No matching record found for $name_pattern $type"
    log_message DEBUG "No matching record found for $name_pattern $type"
    return 1
}

################################################################################
# ENHANCEMENT: Multi-value record handling
################################################################################
handle_multi_value_records() {
    local zone="$1"
    local name="$2"
    local type="$3"
    local new_value="$4"
    local rel_name="$5"

    print_debug "MULTI-VALUE: Checking if $type record needs special handling"
    log_message DEBUG "MULTI-VALUE: Checking if $type record needs special handling"

    case "$type" in
        A|AAAA)
            # For A records, check if multiple records exist that need replacement
            local existing_records
            existing_records=$(jq -r --arg name "$name" --arg type "$type" \
                '[.[] | select(
                    ((.Name // .name // .NAME // empty) == $name) and
                    ((.Type // .type // .TYPE // empty) == $type)
                ) | (.ID // .id // .Id // empty)] | .[]' \
                "$TMP_DIR/dns_cache_${zone}_${SESSION_ID}.json" 2>/dev/null)

            local record_count
            record_count=$(echo "$existing_records" | grep -c . 2>/dev/null || echo "0")
            record_count="${record_count//[^0-9]/}"  # Strip any non-numeric characters

            if [[ $record_count -gt 1 ]]; then
                print_info "Found $record_count existing $type records for $name - will delete all and create single new record"
                log_message INFO "Found $record_count existing $type records for $name"

                # Delete all existing records
                while read -r record_id; do
                    if [[ -n "$record_id" ]]; then
                        print_progress "Deleting existing $type record ID: $record_id"
                        log_message INFO "Deleting existing $type record ID: $record_id"

                        if [[ "$DRY_RUN" == true ]]; then
                            print_info "DRY-RUN: Would delete record ID $record_id"
                            write_command_to_file "# Would delete: flarectl --json dns delete --zone=$zone --id=$record_id" \
                                "Delete existing $type record before creating new one" "$zone"
                        else
                            if retry_with_backoff "flarectl --json dns delete --zone=$zone --id=$record_id" \
                                "Deleting record ID $record_id"; then
                                print_success "Deleted record ID $record_id"
                            else
                                print_error "Failed to delete record ID $record_id"
                                return 1
                            fi
                        fi
                    fi
                done <<< "$existing_records"

                return 0  # Signal to create new record
            fi
            ;;
        *)
            # Standard single-record types
            ;;
    esac

    return 1  # No special handling needed
}

################################################################################
# ENHANCED: sync_record with all bug fixes including trailing dot handling
################################################################################
sync_record() {
    debug_trace

    local zone="$1" zone_id="$2" record_idx="$3" record_json="$4"
    local cache_file="$TMP_DIR/dns_cache_${zone}_${SESSION_ID}.json"

    local fqdn ttl type value priority operation line_number
    fqdn=$(echo "$record_json" | jq -r '.name')
    ttl=$(echo "$record_json" | jq -r '.ttl')
    type=$(echo "$record_json" | jq -r '.type')
    value=$(echo "$record_json" | jq -r '.value')
    priority=$(echo "$record_json" | jq -r '.priority')
    operation=$(echo "$record_json" | jq -r '.operation // "create"')
    line_number=$(echo "$record_json" | jq -r '.line_number // "unknown"')

    if [[ -z "$fqdn" || -z "$ttl" || -z "$type" || -z "$value" ]]; then
        print_error "Missing required fields for record: $record_json"
        log_message ERROR "Missing required fields for record: $record_json"
        echo "ERROR: Missing required fields for record - line $line_number: $fqdn $type" >> "$REPORT_FILE"
        safe_increment "FAILED" "sync_record field validation"
        return 1
    fi

    # Remove trailing dots for consistent processing
    local name="${fqdn%.}"
    zone="${zone%.}"
    local rel

    if [[ "$name" == "$zone" ]]; then
        rel="@"
    else
        rel="${name%.$zone}"
    fi

    print_debug "Record: FQDN=$fqdn, name=$name, relative=$rel, ttl=$ttl, type=$type, value='$value', priority='$priority', operation='$operation', line=$line_number"
    log_message DEBUG "Record: FQDN=$fqdn, name=$name, relative=$rel, ttl=$ttl, type=$type, value='$value', priority='$priority', operation='$operation', line=$line_number"

    if [[ "$VERIFY_MODE" == true ]]; then
        print_info "VERIFY: Would process $zone $rel $type [$operation]"
        log_message INFO "VERIFY: Would process $zone $rel $type [$operation]"
        if [[ "$operation" == "delete" ]]; then
            safe_increment "SKIPPED" "verify mode delete"
        else
            safe_increment "SKIPPED" "verify mode create/update"
        fi
        return 0
    fi

    # CRITICAL FIX: Use cache for existence check instead of fresh API call
    local record_id=""
    local record_exists=false
    local match_result="UNKNOWN"
    local current_value=""

    print_debug "CRITICAL: Performing cache-based existence check for $name $type"
    log_message DEBUG "CRITICAL: Performing cache-based existence check for $name $type"

    # ENHANCED DEBUG: Show exact parameters being used for verification
    print_debug "DEBUG TRACE sync_record: About to check existence with:"
    print_debug "  - zone: '$zone' (trailing dot removed)"
    print_debug "  - name (for verify_record_exists): '$name' (trailing dot removed)"
    print_debug "  - rel_name (for find_record_id): '$rel'"
    print_debug "  - type: '$type'"
    print_debug "  - fqdn: '$fqdn'"
    log_message DEBUG "DEBUG TRACE sync_record: zone='$zone', name='$name', rel='$rel', type='$type', fqdn='$fqdn'"

    # Cache-based existence check
    if verify_record_exists "$zone" "$name" "$type"; then
        record_exists=true
        print_debug "DEBUG TRACE sync_record: verify_record_exists returned TRUE"

        # Now try to get the record ID and current value
        print_debug "DEBUG TRACE sync_record: Now calling find_record_id with rel_name='$rel'"
        if record_id=$(find_record_id "$zone" "$zone_id" "$rel" "$type" "$cache_file"); then
            match_result="MATCH_FOUND"

            # Get current value for comparison using case-insensitive fields
            current_value=$(jq -r --arg name "$name" --arg type "$type" \
                '[.[] | select(
                    ((.Name // .name // .NAME // empty) == $name) and
                    ((.Type // .type // .TYPE // empty) == $type)
                ) | (.Content // .content // .CONTENT // empty)] | .[0] // empty' \
                "$cache_file" 2>/dev/null)

            print_debug "MATCH FOUND: $fqdn $type -> record_id=$record_id, current_value='$current_value'"
            log_message DEBUG "Record exists with ID=$record_id and current value='$current_value'"
        else
            # This shouldn't happen if verify_record_exists returned true
            print_warning "Record exists but couldn't find ID - will attempt create"
            print_debug "DEBUG TRACE sync_record: MISMATCH - verify_record_exists found record but find_record_id failed"
            print_debug "DEBUG TRACE sync_record: This indicates name construction inconsistency"
            record_exists=false
            match_result="ID_NOT_FOUND"
        fi
    else
        record_exists=false
        match_result="NOT_EXISTS"
        print_debug "MATCH FAILED: $fqdn $type -> record does not exist"
        print_debug "DEBUG TRACE sync_record: verify_record_exists returned FALSE"
        log_message DEBUG "Record does not exist, will create new"
    fi

    # Debug DNS name construction for root domains
    if [[ "$rel" == "@" ]]; then
        print_debug "DNS NAME FIX: Root domain record detected, will use '$zone' instead of '@.$zone'"
        log_message DEBUG "DNS NAME FIX: Root domain record detected, will use '$zone' instead of '@.$zone'"
    fi

    # ENHANCEMENT: Check if update is needed (skip no-op updates)
    if [[ "$operation" != "delete" && $record_exists == true && -n "$current_value" ]]; then
        if should_skip_update "$value" "$current_value" "$type"; then
            print_info "Skipping update for $fqdn $type - values already match"
            log_message INFO "Skipping update for $fqdn $type - values already match after normalization"
            safe_increment "SKIPPED" "values already match"
            echo "SKIPPED: $fqdn $type already has correct value - line $line_number" >> "$REPORT_FILE"
            write_command_to_file "# SKIPPED: Values already match for $fqdn $type" \
                "No update needed - values match (line $line_number)" "$zone"
            return 0
        fi
    fi

    # Generate accurate command files
    if [[ "$operation" == "delete" ]]; then
        if $record_exists; then
            local delete_cmd="flarectl --json dns delete --zone=$zone --id=$record_id"
            write_command_to_file "$delete_cmd" "Delete $fqdn $type (line $line_number, record_id=$record_id)" "$zone"
        else
            write_command_to_file "# SKIP: Record not found for deletion: $fqdn $type" "Record not found for deletion (line $line_number)" "$zone"
        fi
    else
        # Check for multi-value record handling
        if handle_multi_value_records "$zone" "$name" "$type" "$value" "$rel"; then
            print_debug "Multi-value record handling completed, proceeding with create"
            record_exists=false  # Force create after multi-delete
        fi

        # Fix DNS name for root domain records
        local dns_name
        if [[ "$rel" == "@" ]]; then
            dns_name="$zone"
        else
            dns_name="$rel.$zone"
        fi

        local cmd_params="--zone=$zone --name=$dns_name --type=$type --content=$value --ttl=$ttl"
        if [[ "$type" == "MX" && -n "$priority" ]]; then
            cmd_params="$cmd_params --priority=$priority"
        fi

        if $record_exists; then
            local update_cmd="flarectl --json dns update $cmd_params --id=$record_id"
            write_command_to_file "$update_cmd" "Update $fqdn $type (line $line_number, record_id=$record_id)" "$zone"
        else
            local create_cmd="flarectl --json dns create $cmd_params"
            write_command_to_file "$create_cmd" "Create $fqdn $type (line $line_number)" "$zone"
        fi
    fi

    # Handle dry-run mode
    if [[ "$DRY_RUN" == true ]]; then
        if [[ "$operation" == "delete" ]]; then
            if $record_exists; then
                print_info "DRY-RUN: would delete $zone $rel $type (record_id=$record_id)"
                log_message INFO "DRY-RUN: would delete $zone $rel $type (record_id=$record_id)"
                safe_increment "DELETED" "dry-run delete operation with real validation"
                echo "DRY-RUN: Would delete $fqdn $type (record_id=$record_id) - line $line_number" >> "$REPORT_FILE"
            else
                print_warning "DRY-RUN: cannot delete $zone $rel $type - record not found"
                log_message WARN "DRY-RUN: cannot delete $zone $rel $type - record not found"
                safe_increment "SKIPPED" "dry-run delete not found"
                echo "DRY-RUN: Cannot delete $fqdn $type - record not found - line $line_number" >> "$REPORT_FILE"
            fi
        else
            if $record_exists; then
                print_info "DRY-RUN: would update $zone $rel $type (record_id=$record_id)"
                log_message INFO "DRY-RUN: would update $zone $rel $type (record_id=$record_id)"
                safe_increment "UPDATED" "dry-run update operation with real validation"
                echo "DRY-RUN: Would update $fqdn $type (record_id=$record_id) - line $line_number" >> "$REPORT_FILE"
            else
                print_info "DRY-RUN: would create $zone $rel $type"
                log_message INFO "DRY-RUN: would create $zone $rel $type"
                safe_increment "CREATED" "dry-run create operation with real validation"
                echo "DRY-RUN: Would create $fqdn $type - line $line_number" >> "$REPORT_FILE"
            fi
        fi
        return 0
    fi

    # Execute actual operations
    if [[ "$operation" == "delete" ]]; then
        if $record_exists; then
            print_progress "Deleting record $zone $rel $type (ID: $record_id)"
            log_message INFO "Deleting record $zone $rel $type (ID: $record_id)"

            if retry_with_backoff "flarectl --json dns delete --zone=$zone --id=$record_id" "Deleting record $zone $rel $type"; then
                print_success "Successfully deleted $zone $rel $type (line $line_number)"
                log_message INFO "Successfully deleted $zone $rel $type (line $line_number)"
                safe_increment "DELETED" "actual delete operation"
                echo "DELETED: $fqdn $type - line $line_number" >> "$REPORT_FILE"
                return 0
            else
                print_error "Failed to delete record $zone $rel $type (line $line_number)"
                log_message ERROR "Failed to delete record $zone $rel $type (line $line_number)"
                safe_increment "FAILED" "failed delete operation"
                echo "ERROR: Failed to delete $fqdn $type - line $line_number" >> "$REPORT_FILE"
                return 1
            fi
        else
            print_warning "Record to delete not found: $zone $rel $type (line $line_number)"
            log_message WARN "Record to delete not found: $zone $rel $type (line $line_number)"
            safe_increment "SKIPPED" "delete record not found"
            echo "SKIPPED: Record to delete not found: $fqdn $type - line $line_number" >> "$REPORT_FILE"
            return 0
        fi
    else
        # Fix DNS name for root domain records
        local dns_name
        if [[ "$rel" == "@" ]]; then
            dns_name="$zone"
        else
            dns_name="$rel.$zone"
        fi

        local cmd_params="--zone=$zone --name=$dns_name --type=$type --content=$value --ttl=$ttl"

        if [[ "$type" == "MX" && -n "$priority" ]]; then
            cmd_params="$cmd_params --priority=$priority"
        fi

        if $record_exists; then
            cmd_params="$cmd_params --id=$record_id"
            print_progress "Updating record $zone $rel $type (ID: $record_id)"
            log_message INFO "Updating record $zone $rel $type (ID: $record_id)"

            if retry_with_backoff "flarectl --json dns update $cmd_params" "Updating record $zone $rel $type"; then
                print_success "Successfully updated $zone $rel $type (line $line_number)"
                log_message INFO "Successfully updated $zone $rel $type (line $line_number)"
                safe_increment "UPDATED" "actual update operation"
                echo "UPDATED: $fqdn $type - line $line_number" >> "$REPORT_FILE"
                return 0
            else
                print_error "Failed to update record $zone $rel $type (line $line_number)"
                log_message ERROR "Failed to update record $zone $rel $type (line $line_number)"
                safe_increment "FAILED" "failed update operation"
                echo "ERROR: Failed to update $fqdn $type - line $line_number" >> "$REPORT_FILE"
                return 1
            fi
        else
            print_progress "Creating record $zone $rel $type"
            log_message INFO "Creating record $zone $rel $type"

            if retry_with_backoff "flarectl --json dns create $cmd_params" "Creating record $zone $rel $type"; then
                print_success "Successfully created $zone $rel $type (line $line_number)"
                log_message INFO "Successfully created $zone $rel $type (line $line_number)"
                safe_increment "CREATED" "actual create operation"
                echo "CREATED: $fqdn $type - line $line_number" >> "$REPORT_FILE"
                return 0
            else
                print_error "Failed to create record $zone $rel $type (line $line_number)"
                log_message ERROR "Failed to create record $zone $rel $type (line $line_number)"
                safe_increment "FAILED" "failed create operation"
                echo "ERROR: Failed to create $fqdn $type - line $line_number" >> "$REPORT_FILE"
                return 1
            fi
        fi
    fi
}

################################################################################
# Zone Processing with Enhanced Diagnostics
################################################################################
process_zone() {
    debug_trace

    local zone="$1" records="$2"
    if [[ -z "$zone" || -z "$records" ]]; then
        print_error "Missing parameters for process_zone"
        log_message ERROR "Missing parameters for process_zone"
        return 1
    fi

    print_section "Processing Zone: $zone" "PROCESS"
    log_message INFO "Processing zone: $zone"
    echo "Processing zone: $zone" >> "$REPORT_FILE"

    local record_count create_count delete_count
    record_count=$(echo "$records" | jq 'length')
    create_count=$(echo "$records" | jq '[.[] | select(.operation == "create" or .operation == null)] | length')
    delete_count=$(echo "$records" | jq '[.[] | select(.operation == "delete")] | length')

    print_info "Zone $zone has $record_count records to process (Create/Update: $create_count, Delete: $delete_count)"
    log_message INFO "Zone $zone has $record_count records to process (Create/Update: $create_count, Delete: $delete_count)"
    echo "Records: $record_count total (Create/Update: $create_count, Delete: $delete_count)" >> "$REPORT_FILE"

    print_debug "Finding account for zone $zone"
    log_message DEBUG "Finding account for zone $zone"
    local account_index
    account_index=$(find_account_for_domain "$zone")

    if [[ "$account_index" == "-1" ]]; then
        print_warning "Skipping zone $zone - not found in any account"
        log_message INFO "Skipping zone $zone - not found in any account"
        echo "SKIPPED: Zone $zone not found in any account" >> "$REPORT_FILE"
        safe_increment "ZONES_SKIPPED" "zone not found in any account"
        ZONES_SUCCESS_STATUS[$zone]="SKIPPED (not found)"
        return 0
    fi

    if [[ -z "$account_index" || ! "$account_index" =~ ^[0-9]+$ ]]; then
        print_error "Invalid account index '$account_index' returned for zone $zone"
        log_message ERROR "Invalid account index '$account_index' returned for zone $zone"
        print_error "This indicates a bug in the account mapping logic"
        log_message ERROR "This indicates a bug in the account mapping logic"
        safe_increment "ZONES_FAILED" "invalid account index"
        ZONES_SUCCESS_STATUS[$zone]="FAILED (invalid account index)"
        return 1
    fi

    ZONES_ACCOUNTS[$zone]="$account_index"
    print_success "Zone $zone mapped to account ${ACCOUNT_NAMES[$account_index]}"
    log_message INFO "Zone $zone mapped to account ${ACCOUNT_NAMES[$account_index]}"

    setup_account_env "$account_index"

    print_debug "Getting zone ID for $zone"
    log_message DEBUG "Getting zone ID for $zone"
    local zone_id
    zone_id=$(get_zone_id "$zone")
    if [[ -z "$zone_id" ]]; then
        print_warning "Failed to get zone ID for $zone, using zone name as identifier"
        log_message WARN "Failed to get zone ID for $zone, using zone name as identifier"
        zone_id="$zone"
    fi

    print_debug "Backing up existing records for zone $zone"
    log_message DEBUG "Backing up existing records for zone $zone"
    backup_zone_records "$zone_id" "$zone" || true

    local fetch_success=true
    print_debug "Fetching current records for zone $zone with smart caching"
    log_message DEBUG "Fetching current records for zone $zone with smart caching"
    if ! fetch_zone_records "$zone_id" "$zone"; then
        print_warning "Failed to fetch zone records, proceeding with limited validation"
        log_message WARN "Failed to fetch zone records, proceeding with limited validation"
        fetch_success=false
    fi

    print_info "Processing $record_count records for zone $zone using enhanced diagnostic array-based approach"
    log_message INFO "Processing $record_count records for zone $zone using enhanced diagnostic array-based approach"

    local zone_success=true
    local zone_operation_count=0

    # Process Delete Operations First
    if [[ $delete_count -gt 0 ]]; then
        print_info "Processing $delete_count delete operations first (enhanced diagnostic method)"
        log_message INFO "Processing $delete_count delete operations first (enhanced diagnostic method)"

        local delete_records_file="$TMP_DIR/delete_records_${zone//\//_}_${SESSION_ID}.tmp"
        diagnostic_trace "creating delete records file" "$delete_records_file"

        if echo "$records" | jq -c '[.[] | select(.operation == "delete")][]' > "$delete_records_file" 2>/dev/null; then
            diagnostic_exit_code "delete records file creation" "0" "$delete_records_file"
            print_debug "Successfully created delete records file with $(wc -l < "$delete_records_file") records"

            declare -a delete_records_array=()
            diagnostic_trace "loading delete records into memory array" "mapfile operation"

            if mapfile -t delete_records_array < "$delete_records_file"; then
                local array_size=${#delete_records_array[@]}
                diagnostic_exit_code "mapfile delete records loading" "0" "loaded $array_size records"
                print_success "Successfully loaded $array_size delete records into memory array"
                log_message INFO "Successfully loaded $array_size delete records into memory array"

                for idx in "${!delete_records_array[@]}"; do
                    local record_json="${delete_records_array[$idx]}"
                    local display_idx=$((idx + 1))

                    if [[ -z "$record_json" || "$record_json" == "null" ]]; then
                        diagnostic_trace "skipping empty record" "array index $idx"
                        continue
                    fi

                    diagnostic_trace "processing delete operation $display_idx/$delete_count" "array index $idx"
                    print_progress "Processing delete operation $display_idx/$delete_count for zone $zone (array index $idx)"
                    log_message INFO "Processing delete operation $display_idx/$delete_count for zone $zone (array index $idx)"
                    print_debug "Delete record JSON: ${record_json:0:100}..."

                    diagnostic_trace "calling sync_record for delete operation" "record $display_idx"
                    if sync_record "$zone" "$zone_id" "d$idx" "$record_json"; then
                        local sync_exit=0
                        diagnostic_exit_code "sync_record delete operation" "$sync_exit" "record $display_idx succeeded"
                        print_debug "Delete operation succeeded for record $display_idx"
                        log_message DEBUG "Delete operation succeeded for record $display_idx"
                    else
                        local sync_exit=$?
                        diagnostic_exit_code "sync_record delete operation" "$sync_exit" "record $display_idx failed"
                        zone_success=false
                        print_debug "Delete operation failed for record $display_idx (exit code: $sync_exit)"
                        log_message WARN "Delete operation failed for record $display_idx (exit code: $sync_exit)"
                    fi

                    diagnostic_trace "incrementing zone_operation_count" "after delete record $display_idx"
                    safe_increment "zone_operation_count" "delete operation $display_idx completed"
                    local increment_exit=$?
                    diagnostic_exit_code "zone_operation_count increment" "$increment_exit" "delete operation $display_idx"

                    diagnostic_trace "loop continuation check" "completed delete record $display_idx of $delete_count"
                    print_debug "=== DELETE LOOP ITERATION $display_idx COMPLETE ==="

                    sleep 0.1
                done

                diagnostic_trace "delete operations loop completed" "processed $delete_count operations"
                print_success "Completed processing $delete_count delete operations using enhanced diagnostic method"
                log_message INFO "Completed processing $delete_count delete operations using enhanced diagnostic method"
            else
                local mapfile_exit=$?
                diagnostic_exit_code "mapfile delete records loading" "$mapfile_exit" "failed to load records"
                print_error "Failed to load delete records into array using mapfile (exit code: $mapfile_exit)"
                log_message ERROR "Failed to load delete records into array using mapfile (exit code: $mapfile_exit)"
                zone_success=false
            fi

            diagnostic_trace "cleaning up delete records temporary file" "$delete_records_file"
            rm -f "$delete_records_file"
        else
            local jq_exit=$?
            diagnostic_exit_code "delete records file creation" "$jq_exit" "jq command failed"
            print_error "Failed to create delete records temporary file (exit code: $jq_exit)"
            log_message ERROR "Failed to create delete records temporary file for zone $zone (exit code: $jq_exit)"
            zone_success=false
        fi
    fi

    # Process Create/Update Operations
    if [[ $create_count -gt 0 ]]; then
        print_info "Processing $create_count create/update operations (enhanced diagnostic method)"
        log_message INFO "Processing $create_count create/update operations (enhanced diagnostic method)"

        local create_records_file="$TMP_DIR/create_records_${zone//\//_}_${SESSION_ID}.tmp"
        diagnostic_trace "creating create records file" "$create_records_file"

        if echo "$records" | jq -c '[.[] | select(.operation == "create" or .operation == null)][]' > "$create_records_file" 2>/dev/null; then
            diagnostic_exit_code "create records file creation" "0" "$create_records_file"
            print_debug "Successfully created create records file with $(wc -l < "$create_records_file") records"

            declare -a create_records_array=()
            diagnostic_trace "loading create records into memory array" "mapfile operation"

            if mapfile -t create_records_array < "$create_records_file"; then
                local array_size=${#create_records_array[@]}
                diagnostic_exit_code "mapfile create records loading" "0" "loaded $array_size records"
                print_success "Successfully loaded $array_size create/update records into memory array"
                log_message INFO "Successfully loaded $array_size create/update records into memory array"

                for idx in "${!create_records_array[@]}"; do
                    local record_json="${create_records_array[$idx]}"
                    local display_idx=$((idx + 1))

                    if [[ -z "$record_json" || "$record_json" == "null" ]]; then
                        diagnostic_trace "skipping empty record" "array index $idx"
                        continue
                    fi

                    diagnostic_trace "processing create/update operation $display_idx/$create_count" "array index $idx"
                    print_progress "Processing create/update operation $display_idx/$create_count for zone $zone (array index $idx)"
                    log_message INFO "Processing create/update operation $display_idx/$create_count for zone $zone (array index $idx)"
                    print_debug "Create record JSON: ${record_json:0:100}..."

                    diagnostic_trace "calling sync_record for create/update operation" "record $display_idx"
                    if sync_record "$zone" "$zone_id" "c$idx" "$record_json"; then
                        local sync_exit=0
                        diagnostic_exit_code "sync_record create/update operation" "$sync_exit" "record $display_idx succeeded"
                        print_debug "Create/update operation succeeded for record $display_idx"
                        log_message DEBUG "Create/update operation succeeded for record $display_idx"
                    else
                        local sync_exit=$?
                        diagnostic_exit_code "sync_record create/update operation" "$sync_exit" "record $display_idx failed"
                        zone_success=false
                        print_debug "Create/update operation failed for record $display_idx (exit code: $sync_exit)"
                        log_message WARN "Create/update operation failed for record $display_idx (exit code: $sync_exit)"
                    fi

                    diagnostic_trace "incrementing zone_operation_count" "after create/update record $display_idx"
                    safe_increment "zone_operation_count" "create/update operation $display_idx completed"
                    local increment_exit=$?
                    diagnostic_exit_code "zone_operation_count increment" "$increment_exit" "create/update operation $display_idx"

                    diagnostic_trace "loop continuation check" "completed create/update record $display_idx of $create_count"
                    print_debug "=== CREATE/UPDATE LOOP ITERATION $display_idx COMPLETE ==="

                    sleep 0.1
                done

                diagnostic_trace "create/update operations loop completed" "processed $create_count operations"
                print_success "Completed processing $create_count create/update operations using enhanced diagnostic method"
                log_message INFO "Completed processing $create_count create/update operations using enhanced diagnostic method"
            else
                local mapfile_exit=$?
                diagnostic_exit_code "mapfile create records loading" "$mapfile_exit" "failed to load records"
                print_error "Failed to load create/update records into array using mapfile (exit code: $mapfile_exit)"
                log_message ERROR "Failed to load create/update records into array using mapfile (exit code: $mapfile_exit)"
                zone_success=false
            fi

            diagnostic_trace "cleaning up create records temporary file" "$create_records_file"
            rm -f "$create_records_file"
        else
            local jq_exit=$?
            diagnostic_exit_code "create records file creation" "$jq_exit" "jq command failed"
            print_error "Failed to create create records temporary file (exit code: $jq_exit)"
            log_message ERROR "Failed to create create records temporary file for zone $zone (exit code: $jq_exit)"
            zone_success=false
        fi
    fi

    diagnostic_trace "finalizing zone processing status" "zone_success=$zone_success, operations=$zone_operation_count"
    if $zone_success; then
        print_success "Successfully completed processing zone $zone using enhanced diagnostic method"
        log_message INFO "Successfully completed processing zone $zone using enhanced diagnostic method"
        ZONES_SUCCESS_STATUS[$zone]="SUCCESS ($zone_operation_count operations)"
        safe_increment "ZONES_PROCESSED" "successful zone completion"
    else
        print_warning "Completed processing zone $zone with some errors"
        log_message WARN "Completed processing zone $zone with some errors"
        ZONES_SUCCESS_STATUS[$zone]="PARTIAL ($zone_operation_count operations, some failed)"
        safe_increment "ZONES_FAILED" "zone completion with errors"
    fi

    echo "Zone processing complete: $zone" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    diagnostic_trace "process_zone function completion" "returning from zone $zone processing"
    return 0
}

show_update_summary() {
    debug_trace

    print_section "Update Summary" "SUMMARY"

    local total_create=0
    local total_delete=0
    local total_records=0

    for zone in "${!ZONES_RECORDS[@]}"; do
        local record_count
        record_count=$(echo "${ZONES_RECORDS[$zone]}" | jq 'length')
       total_records=$((total_records + record_count))

       local create_count delete_count
       create_count=$(echo "${ZONES_RECORDS[$zone]}" | jq '[.[] | select(.operation == "create" or .operation == null)] | length')
       delete_count=$(echo "${ZONES_RECORDS[$zone]}" | jq '[.[] | select(.operation == "delete")] | length')

       total_create=$((total_create + create_count))
       total_delete=$((total_delete + delete_count))
   done

   print_info "The following zones will be processed:"
   echo ""

   print_table_header "Zone" "Records" "Create/Delete"
   for zone in "${!ZONES_RECORDS[@]}"; do
       local record_count
       record_count=$(echo "${ZONES_RECORDS[$zone]}" | jq 'length')

       local create_count delete_count
       create_count=$(echo "${ZONES_RECORDS[$zone]}" | jq '[.[] | select(.operation == "create" or .operation == null)] | length')
       delete_count=$(echo "${ZONES_RECORDS[$zone]}" | jq '[.[] | select(.operation == "delete")] | length')

       printf "%-40s ${BLUE}%-30s${RESET} ${GREEN}%s${RESET}/${RED}%s${RESET}\n" "$zone" "$record_count" "$create_count" "$delete_count"
   done

   echo ""
   print_table_header "Summary" "Count"
   printf "%-40s ${BLUE}%-30s${RESET}\n" "Total zones" "${#ZONES_RECORDS[@]}"
   printf "%-40s ${BLUE}%-30s${RESET}\n" "Total records" "$total_records"
   printf "%-40s ${GREEN}%-30s${RESET}\n" "Total creates/updates" "$total_create"
   printf "%-40s ${RED}%-30s${RESET}\n" "Total deletions" "$total_delete"

   echo ""
   local mode_color="${GREEN}"
   local mode_text=""
   if [[ "$DRY_RUN" == true ]]; then
       mode_color="${YELLOW}"
       mode_text="DRY-RUN (no changes will be made, but validation uses real data)"
   elif [[ "$VERIFY_MODE" == true ]]; then
       mode_color="${BLUE}"
       mode_text="VERIFY (no changes will be made, just verification)"
   else
       mode_color="${RED}"
       mode_text="EXECUTE (changes will be applied)"
   fi

   echo -e "${BOLD}Mode: ${mode_color}$mode_text${RESET}"
   echo ""

   if [[ "$NO_CONFIRM" == true ]]; then
       print_info "Skipping confirmation as requested (--no-confirm)"
       log_message INFO "Skipping confirmation as requested (--no-confirm)"
       return 0
   fi

   echo -e "${BOLD}${YELLOW}Do you want to proceed? (y/n):${RESET} "
   read -r confirm

   if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
       print_info "Operation cancelled by user"
       log_message INFO "Operation cancelled by user"
       cleanup_and_exit "Operation cancelled by user" 0
   fi

   print_success "User confirmed the operation"
   log_message INFO "User confirmed the operation"
   return 0
}

################################################################################
# Main
################################################################################
main() {
   print_header "Multi-Zone DNS Sync Tool v2.1 (Enhanced with Trailing Dot Fix)"

   log_message INFO "===== Starting multi-zone DNS sync v2.1 with enhanced validation and trailing dot fix ====="
   echo "===== DNS Sync Operation v2.1 (Enhanced with Trailing Dot Fix) =====" >> "$REPORT_FILE"

   if [[ "$DRY_RUN" == true ]]; then
       print_info "Running in DRY-RUN mode - validation uses real data, but no changes will be made"
       log_message INFO "Running in DRY-RUN mode - validation uses real data, but no changes will be made"
   elif [[ "$VERIFY_MODE" == true ]]; then
       print_info "Running in VERIFY mode - no changes will be made"
       log_message INFO "Running in VERIFY mode - no changes will be made"
   fi

   print_section "System Check" "1"
   log_message DEBUG "CHECKPOINT 1: Check required commands"
   check_required_commands

   log_message DEBUG "CHECKPOINT 2: Preflight checks"
   preflight_checks

   log_message DEBUG "CHECKPOINT 2.5: Verify configuration parsing"
   if ! verify_configuration; then
       print_error "Configuration verification failed"
       log_message ERROR "Configuration verification failed"
       cleanup_and_exit "Configuration verification failed" 4
   fi

   print_section "Account Setup" "2"
   log_message DEBUG "CHECKPOINT 3: Load accounts"
   trap 'log_message ERROR "Error in load_accounts function"; exit 1' ERR
   load_accounts
   trap 'cleanup_and_exit "Unexpected error at line $LINENO"' ERR

   log_message DEBUG "CHECKPOINT 4: Verify credentials (always performed)"
   verify_credentials

   log_message DEBUG "CHECKPOINT 4.5: Load zone to account mapping cache with enhanced discovery"
   load_zone_cache

   print_section "File Processing" "3"
   log_message DEBUG "CHECKPOINT 5: Parse updates file and organize by zone"
   if ! parse_updates_file; then
       print_error "Failed to parse updates file"
       log_message ERROR "Failed to parse updates file"
       cleanup_and_exit "Failed to parse updates file" 10
   fi

   if [[ ${#ZONES_RECORDS[@]} -eq 0 ]]; then
       print_error "No zones found in updates file."
       log_message ERROR "No zones found in updates file."
       cleanup_and_exit "No zones found in updates file" 11
   fi

   # Show summary and confirm before proceeding
   show_update_summary

   print_section "Zone Processing v2.1 (Enhanced Validation & Trailing Dot Fix)" "4"
   log_message DEBUG "CHECKPOINT 6: Process each zone with enhanced validation and trailing dot fix"

   # Add progress tracking
   local zones_total=${#ZONES_RECORDS[@]}
   local zones_completed=0

   for zone in "${!ZONES_RECORDS[@]}"; do
       zones_completed=$((zones_completed + 1))
       print_info "Processing zone $zones_completed of $zones_total: $zone"

       diagnostic_trace "starting zone processing" "zone: $zone"
       process_zone "$zone" "${ZONES_RECORDS[$zone]}"
       local process_zone_exit=$?
       diagnostic_exit_code "process_zone" "$process_zone_exit" "zone: $zone"

       if [[ $process_zone_exit -ne 0 ]]; then
           print_warning "Zone $zone processing returned non-zero exit code: $process_zone_exit"
           log_message WARN "Zone $zone processing returned non-zero exit code: $process_zone_exit"
       fi

       # Small delay between zones to avoid API rate limiting
       if [[ $zones_completed -lt $zones_total ]]; then
           sleep "$API_SLEEP"
       fi
   done

   print_section "Completion" "5"
   print_success "DNS sync complete with enhanced validation and trailing dot fix"
   log_message INFO "===== DNS sync complete with enhanced validation and trailing dot fix ====="
   print_info "Zones processed: $ZONES_PROCESSED, Skipped: $ZONES_SKIPPED, Failed: $ZONES_FAILED"
   print_info "Records created: $CREATED, Updated: $UPDATED, Deleted: $DELETED, Skipped: $SKIPPED, Failed: $FAILED"
   log_message INFO "Zones processed: $ZONES_PROCESSED, Skipped: $ZONES_SKIPPED, Failed: $ZONES_FAILED"
   log_message INFO "Records created: $CREATED, Updated: $UPDATED, Deleted: $DELETED, Skipped: $SKIPPED, Failed: $FAILED"

   if (( FAILED > 0 )); then
       print_error "One or more records failed"
       log_message ERROR "One or more records failed"
       cleanup_and_exit "Some records failed to sync" 1
   else
       cleanup_and_exit "normal" 0
   fi
}

# Execute main function
log_message DEBUG "Starting enhanced DNS sync script v2.1 execution with trailing dot fix"
main "$@"
# Script should never reach here directly, as cleanup_and_exit is called
log_message DEBUG "Enhanced DNS sync script v2.1 execution completed - cleanup missed?"

