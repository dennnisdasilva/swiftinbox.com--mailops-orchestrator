#!/usr/bin/env bash
# State management for tracking used names across script runs

# Global variables for state management
declare -gA USED_NAMES=()
declare -gA SESSION_NAMES=()
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
    names=$(echo "$json_content" | jq -r '.used_names | to_entries[] | "\(.key)=\(.value)"' 2>/dev/null || true)
    
    if [[ -n "$names" ]]; then
        while IFS='=' read -r key value; do
            USED_NAMES["$key"]="$value"
        done <<< "$names"
    fi
    
    STATE_LOADED=true
    
    # Log state info
    local total_names=$(echo "$json_content" | jq -r '.total_generated // 0')
    local last_run=$(echo "$json_content" | jq -r '.last_run // "never"')
    
    # Safe way to get array count
    local existing_count=0
    if [[ ${#USED_NAMES[@]} -gt 0 ]]; then
        existing_count=${#USED_NAMES[@]}
    fi
    
    echo ";; State loaded: $existing_count existing names tracked" >&2
    echo ";; Last run: $last_run" >&2
    echo ";; Total generated all-time: $total_names" >&2
}

# Save state to JSON file - NEW IMPLEMENTATION
state_save() {
    if [[ "$STATE_MODIFIED" != "true" ]]; then
        return 0
    fi
    
    # Create temporary files for processing
    local temp_file=$(mktemp)
    local keys_file=$(mktemp)
    
    # First, dump all keys to a file to avoid array expansion issues
    {
        # Add existing USED_NAMES keys
        for key in "${!USED_NAMES[@]}"; do
            echo "$key"
        done
        
        # Add new SESSION_NAMES keys (will be deduplicated by sort -u)
        for key in "${!SESSION_NAMES[@]}"; do
            echo "$key"
        done
    } | sort -u > "$keys_file"
    
    # Count total unique keys
    local total=$(wc -l < "$keys_file")
    
    # Build JSON file
    {
        echo '{'
        echo '  "used_names": {'
        
        # Process keys from file
        local first=true
        while IFS= read -r key; do
            if [[ -n "$key" ]]; then
                # Get value from appropriate array
                local value=""
                if [[ -n "${SESSION_NAMES[$key]:-}" ]]; then
                    value="${SESSION_NAMES[$key]}"
                elif [[ -n "${USED_NAMES[$key]:-}" ]]; then
                    value="${USED_NAMES[$key]}"
                fi
                
                if [[ -n "$value" ]]; then
                    if [[ "$first" == "true" ]]; then
                        first=false
                    else
                        echo ","
                    fi
                    # Escape for JSON
                    local escaped_key=$(printf '%s' "$key" | sed 's/\\/\\\\/g; s/"/\\"/g')
                    local escaped_value=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
                    printf '    "%s": "%s"' "$escaped_key" "$escaped_value"
                fi
            fi
        done < "$keys_file"
        
        echo
        echo '  },'
        
        # Add metadata
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        echo "  \"last_run\": \"$timestamp\","
        echo "  \"total_generated\": $total"
        echo '}'
    } > "$temp_file"
    
    # Validate and save
    if jq '.' "$temp_file" > "$STATE_FILE" 2>/dev/null; then
        # Count session entries
        local session_count=0
        if [[ ${#SESSION_NAMES[@]} -gt 0 ]]; then
            session_count=${#SESSION_NAMES[@]}
        fi
        
        echo ";; State saved: $session_count new names added this session" >&2
        echo ";; Total names tracked: $total" >&2
        
        # Clear SESSION_NAMES and update USED_NAMES for next run
        while IFS= read -r key; do
            if [[ -n "$key" ]]; then
                if [[ -n "${SESSION_NAMES[$key]:-}" ]]; then
                    USED_NAMES["$key"]="${SESSION_NAMES[$key]}"
                fi
            fi
        done < "$keys_file"
        SESSION_NAMES=()
    else
        echo "ERROR: Failed to save state" >&2
        echo "Debug: Invalid JSON in $temp_file" >&2
    fi
    
    # Clean up temp files
    rm -f "$temp_file" "$keys_file"
}

# --- STATE QUERY OPERATIONS ---

# Check if a name exists in state
state_exists() {
    local name="$1"
    
    # Check both persistent and session state
    if [[ -n "${USED_NAMES[$name]:-}" ]] || [[ -n "${SESSION_NAMES[$name]:-}" ]]; then
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
    local used_count=0
    local session_count=0
    
    if [[ ${#USED_NAMES[@]} -gt 0 ]]; then
        used_count=${#USED_NAMES[@]}
    fi
    
    if [[ ${#SESSION_NAMES[@]} -gt 0 ]]; then
        session_count=${#SESSION_NAMES[@]}
    fi
    
    echo $((used_count + session_count))
}

# --- STATE MAINTENANCE ---

state_cleanup() {
    local days="${1:-365}"
    echo ";; State cleanup not yet implemented" >&2
}

state_export() {
    local export_file="${1:-state_export.txt}"
    {
        echo "# State export generated at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "# Format: FQDN|IP|Metadata"
        echo
        
        # Use temporary file to avoid array issues
        local temp_keys=$(mktemp)
        
        # Dump all keys
        {
            for key in "${!USED_NAMES[@]}"; do
                echo "$key|${USED_NAMES[$key]}"
            done
            
            for key in "${!SESSION_NAMES[@]}"; do
                echo "$key|${SESSION_NAMES[$key]}"
            done
        } | sort > "$temp_keys"
        
        cat "$temp_keys"
        rm -f "$temp_keys"
        
    } > "$export_file"
    
    echo ";; State exported to $export_file" >&2
}

# --- COLLISION DETECTION ---

find_similar_names() {
    local prefix="$1"
    local max_results="${2:-10}"
    
    {
        for key in "${!USED_NAMES[@]}"; do
            if [[ "$key" == "$prefix"* ]]; then
                echo "$key"
            fi
        done
        
        for key in "${!SESSION_NAMES[@]}"; do
            if [[ "$key" == "$prefix"* ]]; then
                echo "$key"
            fi
        done
    } | sort -u | head -n "$max_results"
}

check_pattern_frequency() {
    local pattern="$1"
    
    # Count in temporary file to avoid issues
    {
        for key in "${!USED_NAMES[@]}"; do
            if [[ "$key" =~ $pattern ]]; then
                echo "x"
            fi
        done
        
        for key in "${!SESSION_NAMES[@]}"; do
            if [[ "$key" =~ $pattern ]]; then
                echo "x"
            fi
        done
    } | wc -l
}

# --- STATISTICS ---

state_stats() {
    local total_persistent=0
    local total_session=0
    
    if [[ ${#USED_NAMES[@]} -gt 0 ]]; then
        total_persistent=${#USED_NAMES[@]}
    fi
    
    if [[ ${#SESSION_NAMES[@]} -gt 0 ]]; then
        total_session=${#SESSION_NAMES[@]}
    fi
    
    local total=$((total_persistent + total_session))
    
    echo "=== State Statistics ===" >&2
    echo "Total names tracked: $total" >&2
    echo "  Persistent: $total_persistent" >&2
    echo "  Session: $total_session" >&2
    echo >&2
    
    echo "Domain distribution:" >&2
    (
        for key in "${!USED_NAMES[@]}"; do
            echo "$key" | cut -d. -f2-
        done
        for key in "${!SESSION_NAMES[@]}"; do
            echo "$key" | cut -d. -f2-
        done
    ) | sort | uniq -c | sort -rn | head -10 >&2
    
    echo >&2
}

# --- RECOVERY OPERATIONS ---

state_backup() {
    if [[ -f "$STATE_FILE" ]]; then
        local backup_name="${STATE_FILE}.backup.$(date +%s)"
        cp "$STATE_FILE" "$backup_name"
        echo ";; State backed up to $backup_name" >&2
    fi
}

state_validate() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "ERROR: State file not found" >&2
        return 1
    fi
    
    if ! jq empty "$STATE_FILE" 2>/dev/null; then
        echo "ERROR: State file is not valid JSON" >&2
        return 1
    fi
    
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
