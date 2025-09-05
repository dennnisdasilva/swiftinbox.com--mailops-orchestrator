#!/usr/bin/env bash
# Utility functions for enhanced A record generation

# --- HASH FUNCTIONS ---

# Generate SHA256 hash and return specified number of characters
hash_sha256() {
    local input="$1"
    local length="${2:-6}"
    printf '%s' "$input" | openssl dgst -sha256 -binary | xxd -p -c32 | head -c"$length"
}

# Generate MD5 hash and return specified number of characters
hash_md5() {
    local input="$1"
    local length="${2:-6}"
    printf '%s' "$input" | openssl dgst -md5 -binary | xxd -p -c16 | head -c"$length"
}

# Generate SHA1 hash and return specified number of characters
hash_sha1() {
    local input="$1"
    local length="${2:-6}"
    printf '%s' "$input" | openssl dgst -sha1 -binary | xxd -p -c20 | head -c"$length"
}

# Generate a composite hash using multiple algorithms
hash_composite() {
    local input="$1"
    local sha_part=$(hash_sha256 "$input" 4)
    local md5_part=$(hash_md5 "$input" 4)
    echo "${sha_part}${md5_part}"
}

# --- BASE CONVERSIONS ---

# Convert decimal to base36 (uppercase)
to_base36() {
    local dec=$1
    local out=""

    if ((dec == 0)); then
        echo "0"
        return
    fi

    while ((dec > 0)); do
        local rem=$((dec % 36))
        if ((rem < 10)); then
            out="${rem}${out}"
        else
            out=$(printf "\\x$(printf '%x' $((rem + 55)))")$out
        fi
        dec=$((dec / 36))
    done

    echo "$out"
}

# Convert decimal to base62 (alphanumeric)
to_base62() {
    local dec=$1
    local chars="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    local out=""

    if ((dec == 0)); then
        echo "0"
        return
    fi

    while ((dec > 0)); do
        local rem=$((dec % 62))
        out="${chars:$rem:1}${out}"
        dec=$((dec / 62))
    done

    echo "$out"
}

# --- RANDOM GENERATORS ---

# Generate random alphanumeric string
random_alnum() {
    local length="${1:-8}"
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c"$length"
}

# Generate random hex string
random_hex() {
    local length="${1:-8}"
    openssl rand -hex "$((length / 2))" | head -c"$length"
}

# Generate random number within range
random_range() {
    local min="$1"
    local max="$2"
    echo $((min + RANDOM % (max - min + 1)))
}

# Generate pronounceable syllable
random_syllable() {
    local consonants="bcdfghjklmnpqrstvwxyz"
    local vowels="aeiou"
    local patterns=("CV" "CVC" "VC" "VCV")
    local pattern="${patterns[RANDOM % ${#patterns[@]}]}"
    local result=""

    for ((i=0; i<${#pattern}; i++)); do
        if [[ "${pattern:i:1}" == "C" ]]; then
            result+="${consonants:RANDOM % ${#consonants}:1}"
        else
            result+="${vowels:RANDOM % ${#vowels}:1}"
        fi
    done

    echo "$result"
}

# Generate multiple pronounceable syllables
random_pronounceable() {
    local syllable_count="${1:-2}"
    local result=""

    for ((i=0; i<syllable_count; i++)); do
        result+=$(random_syllable)
    done

    echo "$result"
}

# --- TIME FUNCTIONS ---

# Get current microseconds
get_microseconds() {
    date +%s%6N
}

# Get time-based seed with jitter
time_seed() {
    local base=$(get_microseconds)
    local jitter=$((RANDOM % 1000))
    echo $((base + jitter))
}

# Generate time-based hash
time_hash() {
    local length="${1:-6}"
    local seed=$(time_seed)
    hash_sha256 "$seed" "$length"
}

# --- STRING MANIPULATION ---

# Shuffle string characters
shuffle_string() {
    local str="$1"
    local shuffled=""
    local chars=()

    # Convert string to array
    for ((i=0; i<${#str}; i++)); do
        chars+=("${str:i:1}")
    done

    # Shuffle array using sort -R
    local indices=()
    while IFS= read -r idx; do
        indices+=("$idx")
    done < <(seq 0 $((${#chars[@]} - 1)) | sort -R)

    # Rebuild string
    for idx in "${indices[@]}"; do
        shuffled+="${chars[$idx]}"
    done

    echo "$shuffled"
}

# Insert random characters into string
insert_random() {
    local str="$1"
    local insert_count="${2:-2}"
    local chars="0123456789abcdefghijklmnopqrstuvwxyz"

    for ((i=0; i<insert_count; i++)); do
        local pos=$((RANDOM % (${#str} + 1)))
        local char="${chars:RANDOM % ${#chars}:1}"
        str="${str:0:pos}${char}${str:pos}"
    done

    echo "$str"
}

# --- IP UTILITIES ---

# Convert IP to integer
ip_to_int() {
    local ip="$1"
    local a b c d
    IFS=. read -r a b c d <<<"$ip"
    echo $((a * 256**3 + b * 256**2 + c * 256 + d))
}

# Calculate checksum from IP
ip_checksum() {
    local ip="$1"
    local int_ip=$(ip_to_int "$ip")
    local sum=0

    while ((int_ip > 0)); do
        sum=$((sum + int_ip % 10))
        int_ip=$((int_ip / 10))
    done

    echo $((sum % 100))
}

# Generate pseudo-random value from IP (deterministic but non-obvious)
ip_entropy() {
    local ip="$1"
    local salt="${2:-enhanced}"
    local hash=$(hash_sha256 "${ip}${salt}" 16)
    echo "$((0x${hash:0:8} % 1000000))"
}

# --- VALIDATION ---

# Check if string is valid DNS label
is_valid_dns_label() {
    local label="$1"

    # Check length (1-63 characters)
    if ((${#label} < 1 || ${#label} > 63)); then
        return 1
    fi

    # Check characters (alphanumeric and hyphens only)
    if [[ ! "$label" =~ ^[a-zA-Z0-9-]+$ ]]; then
        return 1
    fi

    # Cannot start or end with hyphen
    if [[ "$label" =~ ^- ]] || [[ "$label" =~ -$ ]]; then
        return 1
    fi

    return 0
}

# Sanitize string for DNS label
sanitize_dns_label() {
    local label="$1"

    # Convert to lowercase and replace invalid characters with hyphens
    label=$(echo "$label" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')

    # Remove leading/trailing hyphens
    label=$(echo "$label" | sed 's/^-*//' | sed 's/-*$//')

    # Collapse multiple hyphens
    label=$(echo "$label" | sed 's/-\+/-/g')

    # Ensure minimum length
    if [[ -z "$label" ]]; then
        label="srv"
    fi

    # Truncate if too long
    if ((${#label} > 63)); then
        label="${label:0:63}"
        # Remove trailing hyphen if truncation created one
        label="${label%-}"
    fi

    echo "$label"
}

# --- MISC UTILITIES ---

# XOR two strings (for simple obfuscation)
xor_strings() {
    local str1="$1"
    local str2="$2"
    local result=""
    local len=${#str1}

    for ((i=0; i<len; i++)); do
        local c1=$(printf '%d' "'${str1:i:1}")
        local c2=$(printf '%d' "'${str2:i % ${#str2}:1}")
        local xor=$((c1 ^ c2))
        result+=$(printf "\\x$(printf '%x' $xor)")
    done

    echo "$result" | xxd -p | head -c$((len * 2))
}

# Generate CRC-like value (simplified)
simple_crc() {
    local input="$1"
    local poly=0xEDB88320
    local crc=0xFFFFFFFF

    for ((i=0; i<${#input}; i++)); do
        local byte=$(printf '%d' "'${input:i:1}")
        crc=$((crc ^ byte))

        for ((j=0; j<8; j++)); do
            if ((crc & 1)); then
                crc=$(((crc >> 1) ^ poly))
            else
                crc=$((crc >> 1))
            fi
        done
    done

    printf '%x' $((crc ^ 0xFFFFFFFF))
}
