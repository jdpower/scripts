#!/usr/bin/env bash
# ============================================================
#  sysinfo.sh — Ubuntu Hardware & System Inspector
#  Usage: ./sysinfo.sh [-o] [-c] [-r] [-s] [-n] [-g] [-h]
# ============================================================

# ── Colours & Styles ────────────────────────────────────────
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

FG_WHITE='\033[38;5;255m'
FG_ORANGE='\033[38;5;214m'
FG_CYAN='\033[38;5;87m'
FG_GREEN='\033[38;5;120m'
FG_YELLOW='\033[38;5;228m'
FG_RED='\033[38;5;203m'
FG_BLUE='\033[38;5;75m'
FG_PURPLE='\033[38;5;183m'
FG_GREY='\033[38;5;244m'
FG_TEAL='\033[38;5;43m'

# ── Helper: Section Header ───────────────────────────────────
section() {
    local icon="$1"
    local title="$2"
    local color="$3"
    echo ""
    echo -e "${color}${BOLD}  ${icon}  ${title}${RESET}"
    echo -e "${FG_GREY}  $(printf '─%.0s' {1..52})${RESET}"
}

# ── Helper: Key-Value Row ────────────────────────────────────
row() {
    local icon="$1"
    local key="$2"
    local val="$3"
    local vcolor="${4:-$FG_WHITE}"
    printf "  ${FG_GREY}${icon}${RESET}  ${DIM}${FG_WHITE}%-22s${RESET}  ${vcolor}${BOLD}%s${RESET}\n" "$key" "$val"
}

# ── Helper: Percentage bar ───────────────────────────────────
bar() {
    local pct="${1//%/}"
    pct="${pct%%.*}"
    [[ -z "$pct" ]] && pct=0
    local filled=$(( pct * 20 / 100 ))
    local empty=$(( 20 - filled ))
    local color
    if   (( pct >= 90 )); then color="$FG_RED"
    elif (( pct >= 70 )); then color="$FG_ORANGE"
    elif (( pct >= 50 )); then color="$FG_YELLOW"
    else color="$FG_GREEN"
    fi
    printf "${color}["
    printf '█%.0s' $(seq 1 $filled 2>/dev/null) 2>/dev/null || true
    printf '░%.0s' $(seq 1 $empty  2>/dev/null) 2>/dev/null || true
    printf "] %3s%%${RESET}" "$pct"
}

# ── Helper: Usage ────────────────────────────────────────────
usage() {
    echo -e "${FG_ORANGE}${BOLD}  sysinfo.sh${RESET} — Ubuntu Hardware & System Inspector"
    echo ""
    echo -e "  ${FG_WHITE}${BOLD}Usage:${RESET}  ./sysinfo.sh [options]"
    echo ""
    echo -e "  ${FG_WHITE}${BOLD}Options:${RESET}"
    echo -e "    ${FG_CYAN}-o${RESET}   Operating System"
    echo -e "    ${FG_CYAN}-c${RESET}   CPU / Processor"
    echo -e "    ${FG_CYAN}-r${RESET}   Memory (RAM & Swap)"
    echo -e "    ${FG_CYAN}-s${RESET}   Storage"
    echo -e "    ${FG_CYAN}-n${RESET}   Network"
    echo -e "    ${FG_CYAN}-g${RESET}   GPU / Graphics"
    echo -e "    ${FG_CYAN}-h${RESET}   Show this help message"
    echo ""
    echo -e "  ${FG_GREY}No options: runs all sections.${RESET}"
    echo ""
    echo -e "  ${FG_WHITE}${BOLD}Examples:${RESET}"
    echo -e "    ${FG_GREY}./sysinfo.sh -c${RESET}       CPU only"
    echo -e "    ${FG_GREY}./sysinfo.sh -c -r${RESET}    CPU and RAM"
    echo -e "    ${FG_GREY}./sysinfo.sh -o -n${RESET}    OS and Network"
    echo ""
}

# ════════════════════════════════════════════════════════════
#  SECTION FUNCTIONS
# ════════════════════════════════════════════════════════════

show_os() {
    section "🐧" "OPERATING SYSTEM" "$FG_ORANGE"

    OS_NAME=$(grep '^PRETTY_NAME' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Unknown")
    OS_ID=$(grep '^VERSION_ID' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "?")
    CODENAME=$(grep '^VERSION_CODENAME' /etc/os-release 2>/dev/null | cut -d= -f2 || echo "?")
    KERNEL=$(uname -r)
    ARCH=$(uname -m)
    HOSTNAME=$(hostname -f 2>/dev/null || hostname)
    UPTIME=$(uptime -p 2>/dev/null || uptime | awk -F'up' '{print $2}' | awk -F',' '{print $1}' | xargs)
    TIMEZONE=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}' || date +%Z)
    BOOT_TIME=$(who -b 2>/dev/null | awk '{print $3, $4}' || uptime | awk '{print $1}')
    PACKAGES=$(dpkg -l 2>/dev/null | grep -c '^ii' || echo "N/A")
    SHELL_VER="${SHELL##*/} $(${SHELL} --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+[\.\d]*' | head -1)"

    row "🏷️" "Distribution"    "$OS_NAME"     "$FG_ORANGE"
    row "🔢" "Version"         "$OS_ID ($CODENAME)" "$FG_YELLOW"
    row "🐚" "Kernel"          "$KERNEL"      "$FG_CYAN"
    row "📐" "Architecture"    "$ARCH"        "$FG_GREEN"
    row "🖥️" "Hostname"        "$HOSTNAME"    "$FG_WHITE"
    row "⏱️" "Uptime"          "$UPTIME"      "$FG_GREEN"
    row "⏰" "Boot Time"       "$BOOT_TIME"   "$FG_GREY"
    row "🌍" "Timezone"        "$TIMEZONE"    "$FG_BLUE"
    row "📦" "Installed Pkgs"  "$PACKAGES"    "$FG_PURPLE"
    row "🐚" "Shell"           "$SHELL_VER"   "$FG_WHITE"
}

show_cpu() {
    section "⚡" "PROCESSOR (CPU)" "$FG_CYAN"

    CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
    CPU_CORES=$(nproc --all 2>/dev/null || grep -c '^processor' /proc/cpuinfo)
    CPU_THREADS=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo "$CPU_CORES")
    CPU_MHZ=$(grep -m1 'cpu MHz' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs | awk '{printf "%.0f MHz", $1}' || echo "N/A")

    CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
    if [[ "$CPU_VENDOR" == *"AMD"* ]]; then
        CPU_BRAND="AMD"
        VIRT_FLAG="svm"
    else
        CPU_BRAND="Intel"
        VIRT_FLAG="vmx"
    fi

    CPU_FLAGS=$(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null)
    [[ "$CPU_FLAGS" == *"$VIRT_FLAG"* ]] && VIRT="Yes ($CPU_BRAND-V)" || VIRT="No"

    CPU_SOCKETS="1"
    CPU_PHYS_CORES=""
    if command -v dmidecode &>/dev/null; then
        CPU_SOCKETS=$(dmidecode -t processor 2>/dev/null | grep -c 'Socket Designation:' || echo "1")
        CPU_PHYS_CORES=$(dmidecode -t processor 2>/dev/null | grep -m1 'Core Count:' | awk '{print $NF}')
        CPU_MAX_MHZ=$(dmidecode -t processor 2>/dev/null | grep -m1 'Max Speed:' | sed 's/.*Max Speed:[[:space:]]*//')
        CPU_SOCKET_TYPE=$(dmidecode -t processor 2>/dev/null | grep -m1 'Socket Designation:' | sed 's/.*Socket Designation:[[:space:]]*//')
    fi

    CPU_L1=$(grep -m1 'cache size' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
    CPU_L3=""
    if [[ -d /sys/devices/system/cpu/cpu0/cache ]]; then
        for idx in /sys/devices/system/cpu/cpu0/cache/index*/; do
            lvl=$(cat "${idx}level" 2>/dev/null)
            siz=$(cat "${idx}size"  2>/dev/null)
            typ=$(cat "${idx}type"  2>/dev/null)
            [[ "$lvl" == "3" && "$typ" != "Instruction" ]] && CPU_L3="$siz"
        done
    fi

    LOAD=$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null || echo "N/A")

    CPU_USAGE="N/A"
    if command -v mpstat &>/dev/null; then
        CPU_USAGE=$(mpstat 1 1 2>/dev/null | awk '/Average/{printf "%.1f%%", 100-$NF}')
    elif [[ -r /proc/stat ]]; then
        read -r cpu u n s id wa _ < <(grep '^cpu ' /proc/stat)
        sleep 0.3
        read -r cpu2 u2 n2 s2 id2 wa2 _ < <(grep '^cpu ' /proc/stat)
        total=$(( (u2+n2+s2+id2+wa2) - (u+n+s+id+wa) ))
        idle=$(( id2 - id ))
        (( total > 0 )) && CPU_USAGE=$(awk "BEGIN{printf \"%.1f%%\", 100-($idle/$total*100)}")
    fi

    row "🔲" "Model"            "$CPU_MODEL"   "$FG_CYAN"
    row "🏭" "Vendor"           "$CPU_BRAND"   "$FG_ORANGE"
    [[ -n "$CPU_SOCKET_TYPE" ]] && row "🔌" "Socket"   "$CPU_SOCKET_TYPE"  "$FG_GREY"
    row "🧩" "Cores / Threads"  "${CPU_CORES} cores / ${CPU_THREADS} threads" "$FG_YELLOW"
    [[ "$CPU_SOCKETS" -gt 1 ]] 2>/dev/null && row "🖥️ " "Physical Sockets" "$CPU_SOCKETS" "$FG_WHITE"
    row "⚡" "Current Speed"    "$CPU_MHZ"     "$FG_WHITE"
    [[ -n "$CPU_MAX_MHZ" ]]     && row "🚀" "Max (Boost) Speed" "$CPU_MAX_MHZ"  "$FG_CYAN"
    [[ -n "$CPU_L3" ]]          && row "🗃️" "L3 Cache"          "$CPU_L3"       "$FG_GREY" \
                                || { [[ -n "$CPU_L1" ]] && row "🗃️ " "Cache" "$CPU_L1" "$FG_GREY"; }
    row "🏋️" "CPU Usage"         "$CPU_USAGE"   "$FG_GREEN"
    row "📊" "Load Avg (1/5/15)" "$LOAD"        "$FG_BLUE"
    row "🧪" "Virtualisation"    "$VIRT"        "$FG_PURPLE"
}

show_ram() {
    section "🧠" "MEMORY (RAM & SWAP)" "$FG_GREEN"

    MEM_TOTAL=$(awk '/MemTotal/{printf "%.1f GiB", $2/1048576}' /proc/meminfo)
    MEM_FREE=$(awk '/MemAvailable/{printf "%.1f GiB", $2/1048576}' /proc/meminfo)
    MEM_USED_RAW=$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf "%.1f", (t-a)/1048576}' /proc/meminfo)
    MEM_PCT=$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf "%.0f", (t-a)/t*100}' /proc/meminfo)
    SWAP_TOTAL=$(awk '/SwapTotal/{printf "%.1f GiB", $2/1048576}' /proc/meminfo)
    SWAP_FREE=$(awk '/SwapFree/{printf "%.1f GiB", $2/1048576}' /proc/meminfo)
    SWAP_PCT=$(awk '/SwapTotal/{t=$2}/SwapFree/{f=$2}END{if(t>0) printf "%.0f", (t-f)/t*100; else print "0"}' /proc/meminfo)

    MEM_BAR=$(bar "$MEM_PCT")
    SWAP_BAR=$(bar "$SWAP_PCT")

    row "💾" "Total RAM"        "$MEM_TOTAL"   "$FG_GREEN"
    row "📥" "Used / Available" "${MEM_USED_RAW} GiB / ${MEM_FREE}" "$FG_YELLOW"
    printf "  ${FG_GREY}📊${RESET}  ${DIM}${FG_WHITE}%-22s${RESET}  %s\n" "RAM Usage" "$MEM_BAR"
    row "🔄" "Swap Total"       "$SWAP_TOTAL"  "$FG_GREY"
    printf "  ${FG_GREY}📊${RESET}  ${DIM}${FG_WHITE}%-22s${RESET}  %s\n" "Swap Usage" "$SWAP_BAR"

    echo ""
    echo -e "  ${FG_GREY}RAM Slots:${RESET}"
    if command -v dmidecode &>/dev/null; then
        TOTAL_SLOTS=0
        USED_SLOTS=0
        DIMM_TMP=$(mktemp)
        BLOCK_TMP=$(mktemp)
        dmidecode -t memory 2>/dev/null > "$DIMM_TMP"

        parse_dimm_block() {
            local f="$1"
            [[ -s "$f" ]] || return
            local locator bank size speed mtype mfr part rank confspeed
            locator=$(grep -m1 'Locator:'      "$f" | grep -v 'Bank' | sed 's/.*Locator:[[:space:]]*//' | xargs)
            [[ -z "$locator" ]] && return
            bank=$(grep      -m1 'Bank Locator:'          "$f" | sed 's/.*Bank Locator:[[:space:]]*//' | xargs)
            size=$(grep      -m1 '^\s*Size:'              "$f" | sed 's/.*Size:[[:space:]]*//' | xargs)
            speed=$(grep -m1 'Speed:' "$f" | grep -v 'Configured\|Voltage' | sed 's/.*Speed:[[:space:]]*//' | xargs)
            confspeed=$(grep -m1 'Configured.*Speed:'     "$f" | sed 's/.*Speed:[[:space:]]*//' | xargs)
            mtype=$(grep     -m1 'Type:'                  "$f" | grep -v 'Form\|Error\|Detail\|Configured\|Asset\|Part' | sed 's/.*Type:[[:space:]]*//' | xargs)
            mfr=$(grep       -m1 'Manufacturer:'          "$f" | sed 's/.*Manufacturer:[[:space:]]*//' | xargs)
            part=$(grep      -m1 'Part Number:'           "$f" | sed 's/.*Part Number:[[:space:]]*//' | xargs)
            rank=$(grep      -m1 'Rank:'                  "$f" | sed 's/.*Rank:[[:space:]]*//' | xargs)

            (( TOTAL_SLOTS++ ))
            if [[ "$size" == "No Module Installed" || "$size" == "Unknown" || -z "$size" ]]; then
                printf "  ${FG_GREY}  🔲  %-16s  ${FG_RED}[ EMPTY ]${RESET}\n" "$locator"
                return
            fi
            (( USED_SLOTS++ ))

            [[ -z "$bank" || "$bank" == "Unknown" ]] && bank_str="" || bank_str=" (${bank})"
            if [[ -z "$mtype" || "$mtype" == "Unknown" ]]; then
                type_str="${FG_GREY}DDR?${RESET}"
            else
                type_str="${FG_ORANGE}${BOLD}${mtype}${RESET}"
            fi
            if [[ -z "$speed" || "$speed" == "Unknown" ]]; then
                speed_str=""
            elif [[ -n "$confspeed" && "$confspeed" != "Unknown" && "$confspeed" != "$speed" ]]; then
                speed_str="${FG_CYAN}${speed}${RESET} ${FG_GREY}(@ ${confspeed})${RESET}"
            else
                speed_str="${FG_CYAN}${speed}${RESET}"
            fi
            detail=""
            [[ -n "$mfr"  && "$mfr"  != "Unknown" ]] && detail="${mfr}"
            [[ -n "$part" && "$part" != "Unknown" ]] && detail="${detail:+$detail · }${part}"
            [[ -n "$rank" && "$rank" != "Unknown" ]] && detail="${detail:+$detail · }Rank ${rank}"

            printf "  ${FG_GREEN}  🟩  %-16s${RESET}  ${FG_YELLOW}${BOLD}%-10s${RESET}  %b  %b  ${FG_GREY}%s${RESET}\n" \
                "${locator}${bank_str}" "$size" "$type_str" "$speed_str" "$detail"
        }

        in_block=false
        while IFS= read -r line; do
            if [[ "$line" == Handle* ]] && [[ "$line" =~ [Dd][Mm][Ii] ]] && [[ "$line" =~ type[[:space:]]*17 ]]; then
                parse_dimm_block "$BLOCK_TMP"
                > "$BLOCK_TMP"
                in_block=true
            else
                [[ "$in_block" == true ]] && printf '%s\n' "$line" >> "$BLOCK_TMP"
            fi
        done < "$DIMM_TMP"
        parse_dimm_block "$BLOCK_TMP"

        rm -f "$DIMM_TMP" "$BLOCK_TMP"
        echo ""
        printf "  ${FG_GREY}  📌  %-22s${RESET}  ${FG_WHITE}${BOLD}%s populated / %s total slots${RESET}\n" \
            "Slot Summary" "$USED_SLOTS" "$TOTAL_SLOTS"
    else
        echo -e "  ${FG_GREY}  ⚠️  dmidecode not found — run: sudo apt install dmidecode${RESET}"
        echo -e "  ${FG_GREY}     (sudo privileges also required for slot-level detail)${RESET}"
    fi
}

show_storage() {
    section "💽" "STORAGE" "$FG_YELLOW"

    echo -e "  ${FG_GREY}Physical Disks:${RESET}"
    if command -v lsblk &>/dev/null; then
        while IFS= read -r line; do
            echo -e "  ${FG_YELLOW}  ${line}${RESET}"
        done < <(lsblk -d -o NAME,SIZE,TYPE,ROTA,TRAN,MODEL 2>/dev/null | grep -v '^loop')
    fi

    echo ""
    echo -e "  ${FG_GREY}Filesystem Usage:${RESET}"
    df -h --output=target,size,used,avail,pcent 2>/dev/null | grep -v '^tmpfs\|^udev\|^/dev/loop\|^Filesystem' | while read -r mnt size used avail pct; do
        pct_num="${pct//%/}"
        pct_num="${pct_num// /}"
        [[ -z "$pct_num" || ! "$pct_num" =~ ^[0-9]+$ ]] && continue
        b=$(bar "$pct_num")
        printf "  ${FG_TEAL}%-20s${RESET}  ${FG_GREY}%6s total  %6s used  %6s free${RESET}  %s\n" \
            "$mnt" "$size" "$used" "$avail" "$b"
    done
}

show_network() {
    section "🌐" "NETWORK" "$FG_BLUE"

    ip -br addr 2>/dev/null | while read -r iface state addrs; do
        [[ "$iface" == "lo" ]] && continue
        [[ "$state" == "UP" ]] && sc="${FG_GREEN}●${RESET}" || sc="${FG_RED}●${RESET}"
        printf "  %b  ${FG_WHITE}${BOLD}%-14s${RESET}  ${FG_GREY}%s${RESET}  ${FG_BLUE}%s${RESET}\n" \
            "$sc" "$iface" "$state" "$addrs"
    done

    GW=$(ip route 2>/dev/null | awk '/default/{print $3; exit}')
    DNS=$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | paste -sd', ')
    PUBLIC_IP=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null || echo "unavailable")

    echo ""
    row "🚪" "Default Gateway" "${GW:-N/A}"   "$FG_CYAN"
    row "🔍" "DNS Servers"     "${DNS:-N/A}"  "$FG_CYAN"
    row "🌍" "Public IP"       "$PUBLIC_IP"   "$FG_BLUE"
}

show_gpu() {
    section "🎮" "GPU / GRAPHICS" "$FG_PURPLE"

    GPU_INFO="N/A"
    if command -v lspci &>/dev/null; then
        GPU_INFO=$(lspci 2>/dev/null | grep -iE 'VGA|3D|Display' | sed 's/.*: //' | head -3 | paste -sd' | ')
    fi
    [[ -z "$GPU_INFO" ]] && GPU_INFO="N/A"

    NVIDIA_INFO=""
    if command -v nvidia-smi &>/dev/null; then
        NVIDIA_INFO=$(nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu,temperature.gpu \
            --format=csv,noheader,nounits 2>/dev/null | head -1)
    fi

    row "🖼️ " "Detected GPU"    "$GPU_INFO"    "$FG_PURPLE"
    if [[ -n "$NVIDIA_INFO" ]]; then
        IFS=',' read -r gname gmem_total gmem_used gutil gtemp <<< "$NVIDIA_INFO"
        gname=$(echo "$gname" | xargs)
        gmem_total=$(echo "$gmem_total" | xargs)
        gmem_used=$(echo "$gmem_used" | xargs)
        gutil=$(echo "$gutil" | xargs)
        gtemp=$(echo "$gtemp" | xargs)
        GBAR=$(bar "$gutil")
        row "🟢" "NVIDIA Model"    "$gname"       "$FG_GREEN"
        row "💾" "VRAM"            "${gmem_used} / ${gmem_total} MiB" "$FG_YELLOW"
        printf "  ${FG_GREY}📊${RESET}  ${DIM}${FG_WHITE}%-22s${RESET}  %s\n" "GPU Utilisation" "$GBAR"
    fi
}

# ════════════════════════════════════════════════════════════
#  ARGUMENT PARSING
# ════════════════════════════════════════════════════════════
RUN_OS=false
RUN_CPU=false
RUN_RAM=false
RUN_STORAGE=false
RUN_NETWORK=false
RUN_GPU=false
RUN_ALL=false

if [[ $# -eq 0 ]]; then
    RUN_ALL=true
else
    while getopts ":ocrsngh" opt; do
        case $opt in
            o) RUN_OS=true ;;
            c) RUN_CPU=true ;;
            r) RUN_RAM=true ;;
            s) RUN_STORAGE=true ;;
            n) RUN_NETWORK=true ;;
            g) RUN_GPU=true ;;
            h) usage; exit 0 ;;
            \?) echo -e "${FG_RED}  Unknown option: -${OPTARG}${RESET}"; echo ""; usage; exit 1 ;;
        esac
    done
fi

# ════════════════════════════════════════════════════════════
#  BANNER
# ════════════════════════════════════════════════════════════
clear
echo -e "${FG_ORANGE}${BOLD}"
echo "  ╔═════════════════════════════════════════════════════╗"
echo "  ║  🐧  U B U N T U   S Y S T E M   I N S P E C T O R  ║"
echo "  ╚═════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "${FG_GREY}  Scan started: $(date '+%A, %d %B %Y  %H:%M:%S %Z')${RESET}"

# ════════════════════════════════════════════════════════════
#  RUN SECTIONS
# ════════════════════════════════════════════════════════════
[[ "$RUN_ALL" == true || "$RUN_OS"      == true ]] && show_os
[[ "$RUN_ALL" == true || "$RUN_CPU"     == true ]] && show_cpu
[[ "$RUN_ALL" == true || "$RUN_RAM"     == true ]] && show_ram
[[ "$RUN_ALL" == true || "$RUN_STORAGE" == true ]] && show_storage
[[ "$RUN_ALL" == true || "$RUN_NETWORK" == true ]] && show_network
[[ "$RUN_ALL" == true || "$RUN_GPU"     == true ]] && show_gpu

# ════════════════════════════════════════════════════════════
#  FOOTER
# ════════════════════════════════════════════════════════════
echo ""
echo -e "${FG_GREY}  $(printf '─%.0s' {1..54})${RESET}"
echo -e "  ${FG_ORANGE}${BOLD}✅  Scan complete${RESET}  ${FG_GREY}$(date '+%H:%M:%S')${RESET}"
echo -e "${FG_GREY}  sysinfo.sh · Ubuntu System Inspector${RESET}"
echo ""
