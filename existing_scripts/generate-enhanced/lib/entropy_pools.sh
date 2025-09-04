#!/usr/bin/env bash
# Entropy pools for diverse name generation

# --- EXPANDED TOKEN POOLS ---

# Mythological and legendary (100+ items)
MYTHICS=(
    # Greek/Roman
    zeus hera poseidon hades demeter hephaestus aphrodite dionysus
    athena ares artemis apollo hermes hestia persephone prometheus
    atlas kronos rhea oceanus hyperion theia helios selene eos
    nike iris hecate morpheus thanatos hypnos nemesis tyche
    # Norse
    odin thor freya loki heimdall balder frigg tyr bragi idun
    hel fenrir jormungandr sleipnir huginn muninn valhalla asgard
    # Egyptian
    ra osiris isis horus anubis thoth bastet sekhmet ptah khnum
    sobek hathor amun mut khonsu tefnut shu geb nut
    # Other mythologies
    quetzal amaterasu susanoo raijin fujin benzaiten daikoku
    hanuman ganesha shiva vishnu brahma saraswati lakshmi
    cernunnos morrigan brigid dagda lugh epona taranis
    # Legendary creatures
    dragon phoenix gryphon hydra cerberus pegasus chimera kraken
    basilisk manticore sphinx harpy centaur minotaur cyclops
    valkyrie banshee kelpie wendigo yeti sasquatch mothman
)

# Extended colors (100+ items)
COLORS=(
    # Basic colors
    red blue green yellow orange purple pink brown black white gray
    # Shades
    crimson scarlet ruby burgundy maroon vermillion cherry garnet
    navy azure cobalt sapphire cerulean indigo periwinkle midnight
    emerald jade forest olive sage mint lime chartreuse
    gold amber honey mustard saffron canary lemon butter
    # Exotic colors
    teal turquoise aqua cyan peacock persian viridian malachite
    magenta fuschia orchid mauve lavender lilac violet amethyst
    coral salmon peach apricot tangerine persimmon papaya melon
    chocolate mocha coffee espresso caramel toffee sepia umber
    # Metallic
    silver platinum titanium chrome steel iron copper bronze
    brass pewter zinc nickel aluminum mercury lead graphite
    # Unique
    obsidian onyx jet ebony charcoal slate ash smoke
    ivory pearl alabaster bone cream vanilla coconut chalk
    rainbow prismatic opalescent iridescent holographic aurora
)

# Global locations (150+ items)
LOCS=(
    # US cities
    nyc lax chi hou phx phi sat dal sfo sjc aus bos mia atl den
    sea pdx las dc det min stl tam phx nor okc mem lou bal
    # International cities
    lon par ber rom mad ams bru vie pra bud war ath ist mos
    dub edi gla man bir lee bel lis sto osl cop hel rig tal
    # Asia-Pacific
    tok kyo osa nag sap sen pek sha hkg can sin kul jkt bkk
    man del mum ban che kol dha kar lah teh bag dxb ruh jed
    syd mel bne per akl wel chr sue nan lae por
    # Americas
    mex gdl bog lim bue sao rio bra rec sal lpb ccs uio gye
    hav sdq sju pan san cri gua teg sal man asu mvd scl lqa
    yyz yvr yul yyc yeg yow yhz ywg yqb yxe
    # Africa
    cai jnb cpt dbn plz add abj acc lfw los abv kan nbo
    dar ebb kgl lub mpb tun alg rak cmn dkr lad mpm
)

# Weather and nature terms (100+ items)
WEATHER=(
    storm thunder bolt lightning rain snow hail sleet frost ice
    wind gale breeze zephyr cyclone typhoon hurricane tornado
    cloud nimbus cirrus stratus cumulus alto fog mist haze
    sun sol lunar moon star nova comet meteor asteroid nebula
    dawn dusk twilight aurora sunset sunrise noon midnight
    spring summer autumn fall winter solstice equinox
    ocean wave tide current reef shore beach coast cliff
    mountain peak valley canyon gorge plateau mesa butte
    river stream creek brook rapids waterfall cascade spring
    forest woods grove thicket jungle rainforest savanna prairie
    desert oasis dune mesa badlands tundra taiga steppe
    volcano magma lava ash crater caldera geyser fumarole
    crystal quartz diamond ruby emerald sapphire opal jade
)

# Tech and cyber terms (100+ items)
CYBER=(
    alpha beta gamma delta epsilon zeta eta theta iota kappa
    lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi
    bit byte mega giga tera peta exa zetta yotta
    node link mesh grid cluster matrix array vector tensor
    sync async mutex lock thread fiber coroutine lambda
    hash salt nonce token cipher key vault crypt enigma
    proxy gateway router switch hub bridge relay beacon
    pulse wave form signal carrier band freq phase amp
    core edge vertex graph tree heap stack queue list
    raid mirror stripe span pool volume block chunk
    flux flow stream pipe channel socket port buffer
    quantum photon electron neutron proton quark lepton boson
    neural synapse axon dendrite cortex lobe stem
    crypto ledger chain block proof stake work mine
)

# Biological and chemical terms (80+ items)
BIO=(
    helix strand codon gene allele genome chromosome plasmid
    protein enzyme peptide amino acid lipid steroid hormone
    neuron synapse receptor ligand substrate catalyst inhibitor
    mitosis meiosis prophase telophase anaphase metaphase
    atp adp rna dna mrna trna ribosome nucleotide
    alpha beta gamma delta epsilon kappa lambda sigma
    carbon oxygen nitrogen hydrogen helium neon argon xenon
    lithium sodium magnesium calcium iron copper zinc silver
    methyl ethyl propyl butyl pentyl hexyl heptyl octyl
    cis trans syn anti endo exo ortho meta para
    mono di tri tetra penta hexa hepta octa nona deca
)

# Random adjectives (80+ items)
ADJECTIVES=(
    swift rapid quick fast slow steady stable solid fluid liquid
    bright dark dim pale vivid sharp soft hard rough smooth
    hot cold warm cool frozen molten burning blazing icy frigid
    large small tiny huge vast mini mega micro macro nano
    new old ancient modern retro vintage classic neo post pre
    high low mid upper lower inner outer central peripheral edge
    prime alt backup mirror shadow ghost phantom stealth hidden
    active passive neutral positive negative balanced dynamic static
    quantum digital analog hybrid virtual augmented synthetic organic
)

# Action words (60+ items)
ACTIONS=(
    run jump fly soar glide drift float swim dive plunge
    spin twist turn flip roll tumble bounce spring leap vault
    push pull lift drop catch throw launch blast shoot fire
    cut slice chop hack slash pierce stab thrust parry block
    build make create forge craft shape mold form design construct
    break crash smash bash crush grind pulverize shatter fragment burst
)

# Phonetic alphabet and callsigns
PHONETIC=(
    alfa bravo charlie delta echo foxtrot golf hotel india juliet
    kilo lima mike november oscar papa quebec romeo sierra tango
    uniform victor whiskey xray yankee zulu
)

# Chemical elements (periodic table symbols)
ELEMENTS=(
    h he li be b c n o f ne na mg al si p s cl ar
    k ca sc ti v cr mn fe co ni cu zn ga ge as se br kr
    rb sr y zr nb mo tc ru rh pd ag cd in sn sb te i xe
    cs ba la ce pr nd pm sm eu gd tb dy ho er tm yb lu
    hf ta w re os ir pt au hg tl pb bi po at rn fr ra
)

# Constellation names
CONSTELLATIONS=(
    orion ursa draco leo virgo scorpius sagittarius capricornus
    aquarius pisces aries taurus gemini cancer libra ophiuchus
    cassiopeia perseus andromeda pegasus cygnus lyra aquila
    centaurus lupus corvus crater hydra pyxis vela carina
    phoenix tucana grus pavo indus microscopium telescopium
)

# --- POOL INITIALIZATION ---

init_entropy_pools() {
    # Create combined pools for maximum variety
    MEGA_POOL=()
    MEGA_POOL+=("${MYTHICS[@]}")
    MEGA_POOL+=("${COLORS[@]}")
    MEGA_POOL+=("${WEATHER[@]}")
    MEGA_POOL+=("${CYBER[@]}")
    MEGA_POOL+=("${BIO[@]}")

    # Shuffle mega pool using sort -R
    local temp_pool=()
    while IFS= read -r item; do
        temp_pool+=("$item")
    done < <(printf '%s\n' "${MEGA_POOL[@]}" | sort -R)
    MEGA_POOL=("${temp_pool[@]}")

    # Initialize random seed
    RANDOM=$(($(date +%s) % 32768))
}

# --- POOL ACCESS FUNCTIONS ---

# Get random item from specified pool
get_random_pool_item() {
    local pool_name="$1"
    local pool_ref="${pool_name}[@]"
    local pool=("${!pool_ref}")
    echo "${pool[RANDOM % ${#pool[@]}]}"
}

# Get random item from mega pool
get_mega_pool_item() {
    echo "${MEGA_POOL[RANDOM % ${#MEGA_POOL[@]}]}"
}

# Get multiple unique items from pool
get_unique_pool_items() {
    local pool_name="$1"
    local count="$2"
    local pool_ref="${pool_name}[@]"
    local pool=("${!pool_ref}")

    printf '%s\n' "${pool[@]}" | sort -R | head -n "$count"
}

# Generate random pool combination
get_mixed_pool_items() {
    local count="${1:-3}"
    local pools=("MYTHICS" "COLORS" "WEATHER" "CYBER" "BIO" "ADJECTIVES")
    local result=""

    for ((i=0; i<count; i++)); do
        local pool="${pools[RANDOM % ${#pools[@]}]}"
        local item=$(get_random_pool_item "$pool")
        result="${result}${item}"
    done

    echo "$result"
}

# Get weighted random selection (favor certain pools)
get_weighted_item() {
    local weight=$((RANDOM % 100))

    if ((weight < 30)); then
        get_random_pool_item "CYBER"
    elif ((weight < 50)); then
        get_random_pool_item "MYTHICS"
    elif ((weight < 70)); then
        get_random_pool_item "COLORS"
    elif ((weight < 85)); then
        get_random_pool_item "WEATHER"
    else
        get_random_pool_item "BIO"
    fi
}

# Generate compound token
generate_compound_token() {
    local style="${1:-mixed}"

    case "$style" in
        "tech")
            echo "$(get_random_pool_item CYBER)$(get_random_pool_item ACTIONS)"
            ;;
        "nature")
            echo "$(get_random_pool_item WEATHER)$(get_random_pool_item COLORS)"
            ;;
        "myth")
            echo "$(get_random_pool_item MYTHICS)$(get_random_pool_item ADJECTIVES)"
            ;;
        "bio")
            echo "$(get_random_pool_item BIO)$(get_random_pool_item ELEMENTS)"
            ;;
        "mixed")
            echo "$(get_weighted_item)$(random_range 10 99)"
            ;;
        *)
            get_mega_pool_item
            ;;
    esac
}
