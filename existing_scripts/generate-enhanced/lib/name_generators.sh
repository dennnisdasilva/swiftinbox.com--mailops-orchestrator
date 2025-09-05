#!/usr/bin/env bash
# Name generation functions for diverse naming patterns

# Main name generation dispatcher
generate_name() {
    local style="$1"
    local ip="$2"

    case "$style" in
        0)  generate_quantum_hash "$ip" ;;
        1)  generate_phonetic_soup "$ip" ;;
        2)  generate_uuid_fragment "$ip" ;;
        3)  generate_chemical_compound "$ip" ;;
        4)  generate_matrix_code "$ip" ;;
        5)  generate_weather_pattern "$ip" ;;
        6)  generate_crypto_ticker "$ip" ;;
        7)  generate_bio_sequence "$ip" ;;
        8)  generate_radio_callsign "$ip" ;;
        9)  generate_mesh_node "$ip" ;;
        10) generate_mythic_cipher "$ip" ;;
        11) generate_color_storm "$ip" ;;
        12) generate_time_warp "$ip" ;;
        13) generate_element_fusion "$ip" ;;
        14) generate_constellation_code "$ip" ;;
        *)  generate_stealth_hash "$ip" ;;
    esac
}

# Style 0: Quantum Hash - Multiple hash algorithms with random segments
generate_quantum_hash() {
    local ip="$1"
    local seed=$(time_seed)

    # Choose random hash combination
    local hash_type=$((RANDOM % 4))
    local prefix=""
    local hash_part=""

    case $hash_type in
        0)  # SHA + time
            prefix="qh"
            hash_part=$(hash_sha256 "${ip}${seed}" 6)
            ;;
        1)  # MD5 + composite
            prefix="qm"
            hash_part=$(hash_composite "${ip}${seed}")
            ;;
        2)  # CRC style
            prefix="qc"
            hash_part=$(simple_crc "${ip}${seed}")
            ;;
        3)  # Mixed hash
            prefix="qx"
            local sha=$(hash_sha256 "$ip" 3)
            local md5=$(hash_md5 "$seed" 3)
            hash_part="${sha}${md5}"
            ;;
    esac

    # Add entropy
    local entropy=$(random_range 100 999)
    local position=$((RANDOM % 3))

    case $position in
        0) echo "${prefix}${entropy}${hash_part}" ;;
        1) echo "${prefix}${hash_part}${entropy}" ;;
        2) echo "${prefix}${hash_part:0:3}${entropy}${hash_part:3}" ;;
    esac
}

# Style 1: Phonetic Soup - Random pronounceable syllables
generate_phonetic_soup() {
    local ip="$1"
    local syllable_count=$((2 + RANDOM % 2))
    local name=""

    # Generate base pronounceable part
    name=$(random_pronounceable $syllable_count)

    # Add numeric or character suffix
    local suffix_type=$((RANDOM % 4))
    case $suffix_type in
        0) name="${name}$(random_range 10 99)" ;;
        1) name="${name}$(random_hex 2)" ;;
        2) name="${name}$(to_base36 $(ip_checksum "$ip"))" ;;
        3) name="${name}$(random_alnum 2)" ;;
    esac

    # Occasionally insert hyphen
    if ((RANDOM % 3 == 0)); then
        local pos=$((${#name} / 2))
        name="${name:0:pos}-${name:pos}"
    fi

    echo "$name"
}

# Style 2: UUID Fragment - Partial UUIDs with random positioning
generate_uuid_fragment() {
    local ip="$1"
    local uuid_part=$(random_hex 8)
    local position=$((RANDOM % 4))
    local separator=""

    # Choose separator style
    case $((RANDOM % 3)) in
        0) separator="-" ;;
        1) separator="" ;;
        2) separator="_" ;;
    esac

    # Build name based on position
    case $position in
        0)  # Prefix style
            echo "u${separator}${uuid_part:0:4}${separator}${uuid_part:4:4}"
            ;;
        1)  # Split style
            local mid=$(random_hex 2)
            echo "${uuid_part:0:3}${separator}${mid}${separator}${uuid_part:3:5}"
            ;;
        2)  # Suffix style
            local prefix=$(random_alnum 2)
            echo "${prefix}${separator}${uuid_part:0:6}"
            ;;
        3)  # Mixed style
            local chunk1="${uuid_part:0:2}"
            local chunk2="${uuid_part:2:2}"
            local chunk3="${uuid_part:4:4}"
            echo "${chunk1}${separator}${chunk3}${separator}${chunk2}"
            ;;
    esac
}

# Style 3: Chemical Compound - Element symbols + random numbers
generate_chemical_compound() {
    local ip="$1"
    local element_count=$((2 + RANDOM % 2))
    local compound=""

    # Select random elements
    for ((i=0; i<element_count; i++)); do
        local elem=$(get_random_pool_item "ELEMENTS")
        compound+="$elem"

        # Add subscript number occasionally
        if ((RANDOM % 2 == 0)); then
            compound+="$(random_range 2 9)"
        fi
    done

    # Add suffix
    local suffix_type=$((RANDOM % 3))
    case $suffix_type in
        0) compound+="-$(random_range 10 99)" ;;
        1) compound+="-$(random_hex 3)" ;;
        2) compound+="-$(get_random_pool_item "PHONETIC" | cut -c1-3)" ;;
    esac

    echo "$compound"
}

# Style 4: Matrix Code - Alphanumeric matrices
generate_matrix_code() {
    local ip="$1"
    local pattern=$((RANDOM % 5))
    local name=""

    case $pattern in
        0)  # Grid reference
            name="mx$(random_alnum 1)$(random_range 10 99)$(random_alnum 1)$(random_range 10 99)"
            ;;
        1)  # Matrix notation
            name="m$(random_range 1 9)x$(random_range 1 9)$(random_hex 3)"
            ;;
        2)  # Tensor style
            name="t$(random_alnum 2)$(random_range 100 999)"
            ;;
        3)  # Vector notation
            name="v$(to_base62 $(ip_entropy "$ip"))$(random_alnum 1)"
            ;;
        4)  # Array index
            local dims="$(random_range 1 9)$(random_range 1 9)$(random_range 1 9)"
            name="arr${dims}$(random_hex 2)"
            ;;
    esac

    echo "$name"
}

# Style 5: Weather Pattern - Meteorological terms + codes
generate_weather_pattern() {
    local ip="$1"
    local weather=$(get_random_pool_item "WEATHER")
    local code=""

    # Generate weather code
    local code_type=$((RANDOM % 4))
    case $code_type in
        0)  # Pressure reading
            code="$(random_range 950 1050)"
            ;;
        1)  # Temperature style
            code="$(random_range -20 45)c"
            ;;
        2)  # Wind speed
            code="$(random_range 5 150)kt"
            ;;
        3)  # Mixed code
            code="$(random_alnum 1)$(random_range 10 99)"
            ;;
    esac

    # Combine elements
    local pattern=$((RANDOM % 3))
    case $pattern in
        0) echo "${weather}${code}" ;;
        1) echo "${weather}-${code}" ;;
        2) echo "${weather:0:3}${code}${weather: -1}" ;;
    esac
}

# Style 6: Crypto Ticker - Cryptocurrency-style naming
generate_crypto_ticker() {
    local ip="$1"
    local ticker=""

    # Generate ticker symbol
    local style=$((RANDOM % 4))
    case $style in
        0)  # Classic 3-4 letter
            ticker=$(random_alnum 3 | tr '[:lower:]' '[:upper:]')
            ;;
        1)  # With prefix
            local prefix=$(get_random_pool_item "CYBER" | cut -c1-2)
            ticker="${prefix}$(random_alnum 2)"
            ;;
        2)  # Numeric suffix
            ticker="$(random_alnum 2 | tr '[:lower:]' '[:upper:]')$(random_range 2 99)"
            ;;
        3)  # Extended ticker
            ticker="$(random_alnum 2)$(random_hex 2)"
            ;;
    esac

    # Add chain identifier
    if ((RANDOM % 2 == 0)); then
        local chains=("eth" "bnb" "sol" "ada" "dot" "matic")
        local chain="${chains[RANDOM % ${#chains[@]}]}"
        ticker="${ticker}-${chain}"
    fi

    echo "$ticker"
}

# Style 7: Bio Sequence - DNA/protein-like sequences
generate_bio_sequence() {
    local ip="$1"
    local seq_type=$((RANDOM % 3))
    local sequence=""

    case $seq_type in
        0)  # DNA style
            local bases="acgt"
            for ((i=0; i<6; i++)); do
                sequence+="${bases:RANDOM % 4:1}"
            done
            sequence+="-$(random_range 100 999)"
            ;;
        1)  # Protein style
            local amino="adefghiklmnpqrstvwy"
            for ((i=0; i<4; i++)); do
                sequence+="${amino:RANDOM % ${#amino}:1}"
            done
            sequence+="$(random_range 1 99)"
            ;;
        2)  # Gene notation
            local prefix=$(get_random_pool_item "BIO" | cut -c1-3)
            sequence="${prefix}$(random_range 1 9)$(random_alnum 2)"
            ;;
    esac

    echo "$sequence"
}

# Style 8: Radio Callsign - Aviation/maritime style
generate_radio_callsign() {
    local ip="$1"
    local callsign=""

    # Choose callsign format
    local format=$((RANDOM % 4))
    case $format in
        0)  # Phonetic + number
            local phonetic=$(get_random_pool_item "PHONETIC" | cut -c1-4)
            callsign="${phonetic}$(random_range 10 99)"
            ;;
        1)  # Letter-number pattern
            callsign="$(random_alnum 1 | tr '[:lower:]' '[:upper:]')$(random_range 1 9)$(random_alnum 2 | tr '[:lower:]' '[:upper:]')"
            ;;
        2)  # Maritime style
            callsign="$(random_alnum 2 | tr '[:lower:]' '[:upper:]')$(random_range 100 999)"
            ;;
        3)  # Aviation style
            local prefix="n"
            callsign="${prefix}$(random_range 10 99)$(random_alnum 2)"
            ;;
    esac

    echo "$callsign"
}

# Style 9: Mesh Node - Distributed system naming
generate_mesh_node() {
    local ip="$1"
    local node_id=""

    # Generate node identifier
    local style=$((RANDOM % 4))
    case $style in
        0)  # Hex node ID
            node_id="node-$(random_hex 6)"
            ;;
        1)  # Cluster notation
            local cluster=$(random_alnum 2)
            local node=$(random_range 1 999)
            node_id="c${cluster}-n${node}"
            ;;
        2)  # P2P style
            node_id="p$(random_hex 4)$(random_alnum 2)"
            ;;
        3)  # Mesh coordinates
            local x=$(random_range 0 255)
            local y=$(random_range 0 255)
            node_id="mesh${x}-${y}"
            ;;
    esac

    echo "$node_id"
}

# Style 10: Mythic Cipher - Mythology + encryption style
generate_mythic_cipher() {
    local ip="$1"
    local myth=$(get_random_pool_item "MYTHICS")
    local cipher=""

    # Generate cipher part
    local cipher_type=$((RANDOM % 3))
    case $cipher_type in
        0)  # ROT style
            cipher="$(random_range 1 25)"
            ;;
        1)  # Key style
            cipher="$(random_hex 3)"
            ;;
        2)  # Mixed
            cipher="$(random_alnum 2)$(random_range 1 9)"
            ;;
    esac

    # Combine with variations
    local pattern=$((RANDOM % 4))
    case $pattern in
        0) echo "${myth:0:4}${cipher}" ;;
        1) echo "${myth:0:3}-${cipher}" ;;
        2) echo "${cipher}${myth:0:4}" ;;
        3) echo "${myth:0:2}${cipher}${myth: -2}" ;;
    esac
}

# Style 11: Color Storm - Colors + weather phenomena
generate_color_storm() {
    local ip="$1"
    local color=$(get_random_pool_item "COLORS")
    local storm=""

    # Select storm type
    local storms=("storm" "wind" "gale" "tide" "wave" "surge" "front" "cell")
    storm="${storms[RANDOM % ${#storms[@]}]}"

    # Add identifier
    local id_type=$((RANDOM % 3))
    case $id_type in
        0) storm="${storm}$(random_range 1 99)" ;;
        1) storm="${storm}-$(random_alnum 2)" ;;
        2) storm="$(random_range 1 9)${storm}" ;;
    esac

    # Combine elements
    echo "${color:0:4}${storm}"
}

# Style 12: Time Warp - Time-based with distortion
generate_time_warp() {
    local ip="$1"
    local base_time=$(date +%s)

    # Add time distortion
    local warp=$((RANDOM % 86400))  # Random seconds in a day
    local warped_time=$((base_time + warp))

    # Format time component
    local time_part=$(date -d "@$warped_time" +%H%M)

    # Add prefix
    local prefixes=("tw" "tmp" "chrn" "flux")
    local prefix="${prefixes[RANDOM % ${#prefixes[@]}]}"

    # Add entropy
    local entropy=$(hash_sha256 "${ip}${warped_time}" 3)

    echo "${prefix}${time_part}${entropy}"
}

# Style 13: Element Fusion - Chemical elements fusion
generate_element_fusion() {
    local ip="$1"
    local elem1=$(get_random_pool_item "ELEMENTS")
    local elem2=$(get_random_pool_item "ELEMENTS")

    # Ensure different elements
    while [[ "$elem1" == "$elem2" ]]; do
        elem2=$(get_random_pool_item "ELEMENTS")
    done

    # Add fusion notation
    local fusion_type=$((RANDOM % 3))
    case $fusion_type in
        0)  # Plus notation
            echo "${elem1}p${elem2}$(random_range 1 9)"
            ;;
        1)  # Fusion marker
            echo "${elem1}${elem2}f$(random_hex 2)"
            ;;
        2)  # Reaction style
            echo "${elem1}x${elem2}$(random_range 10 99)"
            ;;
    esac
}

# Style 14: Constellation Code - Star patterns
generate_constellation_code() {
    local ip="$1"
    local constellation=$(get_random_pool_item "CONSTELLATIONS")
    local code=""

    # Generate star code
    local code_type=$((RANDOM % 4))
    case $code_type in
        0)  # Star catalog style
            code="$(random_alnum 1)$(random_range 100 999)"
            ;;
        1)  # Magnitude style
            code="m$(random_range 1 6)$(random_hex 2)"
            ;;
        2)  # Coordinate style
            code="$(random_range 0 23)h$(random_range 0 59)"
            ;;
        3)  # Deep sky object
            code="ngc$(random_range 1 999)"
            ;;
    esac

    # Combine elements
    echo "${constellation:0:3}${code}"
}

# Fallback: Stealth Hash
generate_stealth_hash() {
    local ip="$1"
    local hash=$(hash_composite "${ip}$(time_seed)")
    echo "srv-${hash}"
}
