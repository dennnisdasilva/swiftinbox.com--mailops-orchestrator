#!/usr/bin/env bash
# State management for tracking used names across script runs

# Global variables for state management
declare -A USED_NAMES
declare -A SESSION_NAMES
STATE_LOADED=false
STATE_MODIFIED=false

# --- STATE FILE OPERATIONS ---

# Load state from JSON file
state_load() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "WARNING: State file not found, initializing empty state" >&2
        STATE_LOADED=true
        return 0
    fi

    # Read existing names into associative array
    local json_content
    json_content=$(cat "$STATE_FILE")

    # Parse used_names object
    local names
    names=$(echo "$json_content" | jq -r '.used_names | to_entries[] | "\(.key)=\(.value)"' 2>/dev/null)

    if [[ -n "$names" ]]; then
        while IFS='=' read -r key value; do
            USED_NAMES["$key"]="$value"
        done <<< "$names"
    fi

    STATE_LOADED=true

    # Log state info
    local total_names=$(echo "$json_content" | jq -r '.total_generated // 0')
    local last_run=$(echo "$json_content" | jq -r '.last_run // "never"')

    echo ";; State loaded: ${#USED_NAMES[@]} existing names tracked" >&2
    echo ";; Last run: $last_run" >&2
    echo ";; Total generated all-time: $total_names" >&2
}

# Save state to JSON file
state_save() {
    if [[ "$STATE_MODIFIED" != "true" ]]; then
        return 0
    fi

    # Merge session names into main tracking
    for key in "${!SESSION_NAMES[@]}"; do
        USED_NAMES["$key"]="${SESSION_NAMES[$key]}"
    done

    # Build JSON object
    local json_obj='{"used_names": {}, "last_run": "", "total_generated": 0}'

    # Add all used names
    for key in "${!USED_NAMES[@]}"; do
        local value="${USED_NAMES[$key]}"
        json_obj=$(echo "$json_obj" | jq \
            --arg k "$key" \
            --arg v "$value" \
            '.used_names[$k] = $v')
    done

    # Update metadata
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local total=$((${#USED_NAMES[@]}))

    json_obj=$(echo "$json_obj" | jq \
        --arg ts "$timestamp" \
        --arg total "$total" \
        '.last_run = $ts | .total_generated = ($total | tonumber)')

    # Write to file with pretty formatting
    echo "$json_obj" | jq '.' > "$STATE_FILE"

    echo ";; State saved: ${#SESSION_NAMES[@]} new names added this session" >&2
    echo ";; Total names tracked: $total" >&2
}

# --- STATE QUERY OPERATIONS ---

# Check if a name exists in state
state_exists() {
    local name="$1"

    # Check both persistent and session state
    if [[ -n "${USED_NAMES[$name]}" ]] || [[ -n "${SESSION_NAMES[$name]}" ]]; then
        return 0
    else
        return 1
    fi
}

# Add name to state
state_add() {
    local name="$1"
    local ip="$2"
    local metadata="${3:-}"

    # Add to session names
    if [[ -n "$metadata" ]]; then
        SESSION_NAMES["$name"]="${ip}|${metadata}"
    else
        SESSION_NAMES["$name"]="$ip"
    fi

    STATE_MODIFIED=true
}

# Get total count of tracked names
state_count() {
    echo $(( ${#USED_NAMES[@]} + ${#SESSION_NAMES[@]} ))
}

# --- STATE MAINTENANCE ---

# Clean old entries (optional retention policy)
state_cleanup() {
    local days="${1:-365}"  # Default: keep for 1 year
    local cutoff_date=$(date -d "$days days ago" +%s)
    local cleaned=0

    # This would require storing timestamps with each entry
    # For now, this is a placeholder for future enhancement
    echo ";; State cleanup not yet implemented" >&2
}

# Export state for analysis
state_export() {
    local export_file="${1:-state_export.txt}"

    {
        echo "# State export generated at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "# Format: FQDN|IP|Metadata"
        echo

        # Export persistent names
        for key in "${!USED_NAMES[@]}"; do
            echo "$key|${USED_NAMES[$key]}"
        done | sort

        echo
        echo "# Session names (not yet persisted)"

        # Export session names
        for key in "${!SESSION_NAMES[@]}"; do
            echo "$key|${SESSION_NAMES[$key]}"
        done | sort
    } > "$export_file"

    echo ";; State exported to $export_file" >&2
}

# --- COLLISION DETECTION ---

# Find similar names (for avoiding patterns)
find_similar_names() {
    local prefix="$1"
    local max_results="${2:-10}"
    local similar=()

    # Check both arrays
    for key in "${!USED_NAMES[@]}" "${!SESSION_NAMES[@]}"; do
        if [[ "$key" == "$prefix"* ]]; then
            similar+=("$key")
        fi
    done

    # Return unique results
    printf '%s\n' "${similar[@]}" | sort -u | head -n "$max_results"
}

# Check pattern frequency
check_pattern_frequency() {
    local pattern="$1"
    local count=0

    for key in "${!USED_NAMES[@]}" "${!SESSION_NAMES[@]}"; do
        if [[ "$key" =~ $pattern ]]; then
            ((count++))
        fi
    done

    echo "$count"
}

# --- STATISTICS ---

# Generate state statistics
state_stats() {
    local total_persistent=${#USED_NAMES[@]}
    local total_session=${#SESSION_NAMES[@]}
    local total=$((total_persistent + total_session))

    # Analyze naming patterns
    local style_counts=()
    local prefixes=()

    echo "=== State Statistics ===" >&2
    echo "Total names tracked: $total" >&2
    echo "  Persistent: $total_persistent" >&2
    echo "  Session: $total_session" >&2
    echo >&2

    # Domain distribution
    echo "Domain distribution:" >&2
    (
        for key in "${!USED_NAMES[@]}" "${!SESSION_NAMES[@]}"; do
            echo "$key" | cut -d. -f2-
        done | sort | uniq -c | sort -rn | head -10
    ) >&2

    echo >&2
}

# --- RECOVERY OPERATIONS ---

# Backup state file
state_backup() {
    if [[ -f "$STATE_FILE" ]]; then
        local backup_name="${STATE_FILE}.backup.$(date +%s)"
        cp "$STATE_FILE" "$backup_name"
        echo ";; State backed up to $backup_name" >&2
    fi
}

# Validate state file integrity
state_validate() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "ERROR: State file not found" >&2
        return 1
    fi

    # Check JSON validity
    if ! jq empty "$STATE_FILE" 2>/dev/null; then
        echo "ERROR: State file is not valid JSON" >&2
        return 1
    fi

    # Check required fields
    local has_used_names=$(jq 'has("used_names")' "$STATE_FILE")
    local has_last_run=$(jq 'has("last_run")' "$STATE_FILE")
    local has_total=$(jq 'has("total_generated")' "$STATE_FILE")

    if [[ "$has_used_names" != "true" ]] || \
       [[ "$has_last_run" != "true" ]] || \
       [[ "$has_total" != "true" ]]; then
        echo "ERROR: State file missing required fields" >&2
        return 1
    fi

    echo ";; State file validation passed" >&2
    return 0
}

# Emergency state recovery
state_recover() {
    local backup_pattern="${STATE_FILE}.backup.*"
    local latest_backup=$(ls -t $backup_pattern 2>/dev/null | head -1)

    if [[ -n "$latest_backup" ]] && [[ -f "$latest_backup" ]]; then
        echo ";; Attempting to recover from $latest_backup" >&2
        cp "$latest_backup" "$STATE_FILE"
        state_validate
        return $?
    else
        echo "ERROR: No backup files found for recovery" >&2
        return 1
    fi
}
