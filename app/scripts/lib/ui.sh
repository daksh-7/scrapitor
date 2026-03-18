#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  ui.sh - Terminal UI components for Scrapitor
# ═══════════════════════════════════════════════════════════════════════════════

# ── Terminal Capabilities ─────────────────────────────────────────────────────
UI_UNICODE=false
UI_WIDTH=80
UI_INITIALIZED=false

# ── Colors (ANSI escape codes) ────────────────────────────────────────────────
# Use $'...' syntax so escape codes are interpreted immediately
COLOR_RESET=$'\033[0m'
COLOR_CYAN=$'\033[36m'
COLOR_GREEN=$'\033[32m'
COLOR_YELLOW=$'\033[33m'
COLOR_RED=$'\033[31m'
COLOR_GRAY=$'\033[90m'
COLOR_MAGENTA=$'\033[35m'

# ── Icons ─────────────────────────────────────────────────────────────────────
ICON_SUCCESS="+"
ICON_ERROR="x"
ICON_WARNING="!"
ICON_INFO="o"
ICON_PENDING="."
ICON_ARROW=">"
ICON_BULLET="*"

# ── Box Characters ────────────────────────────────────────────────────────────
BOX_TL="+"
BOX_TR="+"
BOX_BL="+"
BOX_BR="+"
BOX_H="-"
BOX_V="|"
BOX_TEE_L="+"
BOX_TEE_R="+"
BOX_DOUBLE="="

# ── Spinner ───────────────────────────────────────────────────────────────────
SPINNER_FRAMES=('|' '/' '-' '\\')
SPINNER_INDEX=0

# ── Layout ────────────────────────────────────────────────────────────────────
LAYOUT_MAX_WIDTH=78
LAYOUT_INDENT=2
LAYOUT_SPINNER_PAD=68
LAYOUT_BOX_MIN_WIDTH=50

# ── Startup Time ──────────────────────────────────────────────────────────────
STARTUP_TIME=""

# ── ASCII Art Banner ──────────────────────────────────────────────────────────
BANNER_FULL='
███████╗ ██████╗██████╗  █████╗ ██████╗ ██╗████████╗ ██████╗ ██████╗ 
██╔════╝██╔════╝██╔══██╗██╔══██╗██╔══██╗██║╚══██╔══╝██╔═══██╗██╔══██╗
███████╗██║     ██████╔╝███████║██████╔╝██║   ██║   ██║   ██║██████╔╝
╚════██║██║     ██╔══██╗██╔══██║██╔═══╝ ██║   ██║   ██║   ██║██╔══██╗
███████║╚██████╗██║  ██║██║  ██║██║     ██║   ██║   ╚██████╔╝██║  ██║
╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝
'

BANNER_COMPACT='
 ___  ___ _ __ __ _ _ __ (_) |_ ___  _ __ 
/ __|/ __| '"'"'__/ _` | '"'"'_ \| | __/ _ \| '"'"'__|
\__ \ (__| | | (_| | |_) | | || (_) | |   
|___/\___|_|  \__,_| .__/|_|\__\___/|_|   
                   |_|                    
'

# ═══════════════════════════════════════════════════════════════════════════════
#  Initialization
# ═══════════════════════════════════════════════════════════════════════════════

ui_init() {
    if [[ "$UI_INITIALIZED" == "true" ]]; then
        return 0
    fi

    # Detect Unicode support
    if [[ -n "${WT_SESSION:-}" ]] || \
       [[ "${TERM_PROGRAM:-}" == "vscode" ]] || \
       [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]] || \
       [[ "${TERM:-}" == *"256color"* ]] || \
       [[ "${TERM:-}" == "xterm-kitty" ]] || \
       [[ "${TERM:-}" == "alacritty" ]] || \
       [[ -n "${KITTY_WINDOW_ID:-}" ]] || \
       [[ -n "${ALACRITTY_WINDOW_ID:-}" ]] || \
       [[ "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" == *"UTF-8"* ]] || \
       [[ "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" == *"utf8"* ]]; then
        UI_UNICODE=true
    fi

    # Get terminal width
    if command -v tput &>/dev/null; then
        UI_WIDTH=$(tput cols 2>/dev/null || echo 80)
    elif [[ -n "${COLUMNS:-}" ]]; then
        UI_WIDTH="$COLUMNS"
    fi
    UI_WIDTH=$((UI_WIDTH > 60 ? UI_WIDTH : 80))

    # Initialize icons based on capabilities
    if [[ "$UI_UNICODE" == "true" ]]; then
        ICON_SUCCESS="✓"
        ICON_ERROR="✗"
        ICON_WARNING="◆"
        ICON_INFO="○"
        ICON_PENDING="…"
        ICON_ARROW="▶"
        ICON_BULLET="•"
        
        SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        
        BOX_TL="┌"
        BOX_TR="┐"
        BOX_BL="└"
        BOX_BR="┘"
        BOX_H="─"
        BOX_V="│"
        BOX_TEE_L="├"
        BOX_TEE_R="┤"
        BOX_DOUBLE="═"
    fi

    UI_INITIALIZED=true
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Output Functions
# ═══════════════════════════════════════════════════════════════════════════════

show_banner() {
    ui_init
    STARTUP_TIME=$(date +%s)
    
    clear 2>/dev/null || true
    
    local banner
    if (( UI_WIDTH < 60 )); then
        banner="$BANNER_COMPACT"
    else
        banner="$BANNER_FULL"
    fi
    
    echo -e "${COLOR_CYAN}${banner}${COLOR_RESET}"
    echo ""
}

write_status() {
    local message="$1"
    local type="${2:-Info}"
    
    ui_init
    
    local icon color
    case "$type" in
        Success) icon="$ICON_SUCCESS"; color="$COLOR_GREEN" ;;
        Error)   icon="$ICON_ERROR";   color="$COLOR_RED" ;;
        Warning) icon="$ICON_WARNING"; color="$COLOR_YELLOW" ;;
        *)       icon="$ICON_INFO";    color="$COLOR_GRAY" ;;
    esac
    
    local indent
    printf -v indent '%*s' "$LAYOUT_INDENT" ''
    echo -e "${indent}[${color}${icon}${COLOR_RESET}] ${message}"
}

write_spinner() {
    local message="$1"
    
    ui_init
    
    local frame="${SPINNER_FRAMES[$SPINNER_INDEX]}"
    SPINNER_INDEX=$(( (SPINNER_INDEX + 1) % ${#SPINNER_FRAMES[@]} ))
    
    local indent
    printf -v indent '%*s' "$LAYOUT_INDENT" ''
    
    # Clear line and write spinner
    # Use %s for message to avoid issues with % characters in message
    printf "\r%-${LAYOUT_SPINNER_PAD}s" ""
    printf "\r%s[%s%s%s] %s" "$indent" "$COLOR_CYAN" "$frame" "$COLOR_RESET" "$message"
}

clear_spinner_line() {
    printf "\r%-${LAYOUT_SPINNER_PAD}s\r" ""
}

write_subtle() {
    local message="$1"
    local indent
    printf -v indent '%*s' "$LAYOUT_INDENT" ''
    echo -e "${indent}${COLOR_GRAY}${message}${COLOR_RESET}"
}

write_section() {
    local title="$1"
    
    ui_init
    
    local indent
    printf -v indent '%*s' "$LAYOUT_INDENT" ''
    local line_len=$((50 - ${#title}))
    (( line_len < 10 )) && line_len=10
    
    local line=""
    for ((i=0; i<line_len; i++)); do
        line="${line}${BOX_H}"
    done
    
    echo ""
    echo -e "${indent}${COLOR_CYAN}${BOX_H}${BOX_H} ${title} ${COLOR_GRAY}${line}${COLOR_RESET}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
#  LAN IP Detection
# ═══════════════════════════════════════════════════════════════════════════════

get_lan_ip() {
    local ip=""
    
    # Method 1: ip route (Linux, including Termux)
    if command -v ip &>/dev/null; then
        ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n1)
        if [[ -n "$ip" && "$ip" != "127.0.0.1" ]]; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Method 2: hostname -I (Linux, not available on Termux/macOS)
    if command -v hostname &>/dev/null; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
        if [[ -n "$ip" && "$ip" != "127.0.0.1" ]]; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Method 3: ifconfig (macOS/BSD/Termux with net-tools)
    if command -v ifconfig &>/dev/null; then
        ip=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n1)
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Method 4: Android/Termux - try getprop for WiFi IP
    if command -v getprop &>/dev/null; then
        ip=$(getprop dhcp.wlan0.ipaddress 2>/dev/null)
        if [[ -n "$ip" && "$ip" != "127.0.0.1" ]]; then
            echo "$ip"
            return 0
        fi
        # Try alternate property names
        ip=$(getprop wifi.interface 2>/dev/null | xargs -I{} getprop dhcp.{}.ipaddress 2>/dev/null)
        if [[ -n "$ip" && "$ip" != "127.0.0.1" ]]; then
            echo "$ip"
            return 0
        fi
    fi
    
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
#  URL Box Display
# ═══════════════════════════════════════════════════════════════════════════════

show_url_box() {
    local tunnel_url="$1"
    local port="$2"
    
    ui_init
    
    local proxy_url="${tunnel_url}/openrouter-cc"
    local local_url="http://localhost:${port}"
    local lan_ip
    lan_ip=$(get_lan_ip)
    local lan_url=""
    [[ -n "$lan_ip" ]] && lan_url="http://${lan_ip}:${port}"
    
    # Calculate box width
    local dashboard_line="  Dashboard:  ${local_url}"
    local lan_line=""
    [[ -n "$lan_url" ]] && lan_line="  LAN:        ${lan_url}"
    local proxy_line="  Proxy URL:  ${proxy_url}"
    
    local inner_width=${#proxy_line}
    (( ${#dashboard_line} > inner_width )) && inner_width=${#dashboard_line}
    [[ -n "$lan_line" ]] && (( ${#lan_line} > inner_width )) && inner_width=${#lan_line}
    inner_width=$((inner_width + 2))
    
    local indent
    printf -v indent '%*s' "$LAYOUT_INDENT" ''
    
    # Build horizontal border
    local border=""
    for ((i=0; i<inner_width; i++)); do
        border="${border}${BOX_H}"
    done
    
    echo ""
    # Top border
    echo -e "${indent}${COLOR_GRAY}${BOX_TL}${border}${BOX_TR}${COLOR_RESET}"
    
    # Dashboard line
    local padding=$((inner_width - ${#dashboard_line}))
    printf "%s%s%s%s  Dashboard:  %s%s%s" "$indent" "$COLOR_GRAY" "$BOX_V" "$COLOR_RESET" "$COLOR_CYAN" "$local_url" "$COLOR_RESET"
    printf '%*s' "$padding" ''
    echo -e "${COLOR_GRAY}${BOX_V}${COLOR_RESET}"
    
    # LAN line (if available)
    if [[ -n "$lan_url" ]]; then
        padding=$((inner_width - ${#lan_line}))
        printf "%s%s%s%s  LAN:        %s%s%s" "$indent" "$COLOR_GRAY" "$BOX_V" "$COLOR_RESET" "$COLOR_CYAN" "$lan_url" "$COLOR_RESET"
        printf '%*s' "$padding" ''
        echo -e "${COLOR_GRAY}${BOX_V}${COLOR_RESET}"
    fi
    
    # Proxy URL line
    padding=$((inner_width - ${#proxy_line}))
    printf "%s%s%s%s  Proxy URL:  %s%s%s" "$indent" "$COLOR_GRAY" "$BOX_V" "$COLOR_RESET" "$COLOR_GREEN" "$proxy_url" "$COLOR_RESET"
    printf '%*s' "$padding" ''
    echo -e "${COLOR_GRAY}${BOX_V}${COLOR_RESET}"
    
    # Bottom border
    echo -e "${indent}${COLOR_GRAY}${BOX_BL}${border}${BOX_BR}${COLOR_RESET}"
    
    # Hint
    echo ""
    echo -e "${indent}  ${COLOR_GRAY}Copy the Proxy URL and paste it into JanitorAI${COLOR_RESET}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Error Box Display
# ═══════════════════════════════════════════════════════════════════════════════

show_error_box() {
    local title="$1"
    shift
    local details=("$@")
    
    ui_init
    
    # Calculate width
    local header_len=$((${#title} + 12))  # "  x ERROR: " prefix
    local max_detail_len=0
    for line in "${details[@]}"; do
        (( ${#line} > max_detail_len )) && max_detail_len=${#line}
    done
    
    local content_width=$((header_len > max_detail_len + 4 ? header_len : max_detail_len + 4))
    local box_width=$((content_width + 4))
    (( box_width < LAYOUT_BOX_MIN_WIDTH )) && box_width=$LAYOUT_BOX_MIN_WIDTH
    (( box_width > LAYOUT_MAX_WIDTH )) && box_width=$LAYOUT_MAX_WIDTH
    local inner_width=$((box_width - 2))
    
    local indent
    printf -v indent '%*s' "$LAYOUT_INDENT" ''
    
    # Build borders
    local border=""
    local divider=""
    for ((i=0; i<inner_width; i++)); do
        border="${border}${BOX_DOUBLE}"
        divider="${divider}${BOX_H}"
    done
    
    echo ""
    # Top border
    echo -e "${indent}${COLOR_RED}${BOX_TL}${border}${BOX_TR}${COLOR_RESET}"
    
    # Header
    local header="  ${ICON_ERROR} ERROR: ${title}"
    local padding=$((inner_width - ${#header}))
    printf "%s%s%s%s%s" "$indent" "$COLOR_RED" "$BOX_V" "$header" "$COLOR_RESET"
    printf '%*s' "$padding" ''
    echo -e "${COLOR_RED}${BOX_V}${COLOR_RESET}"
    
    # Divider
    echo -e "${indent}${COLOR_RED}${BOX_TEE_L}${divider}${BOX_TEE_R}${COLOR_RESET}"
    
    # Details
    for line in "${details[@]}"; do
        local detail="  ${line}"
        padding=$((inner_width - ${#detail}))
        (( padding < 0 )) && padding=0
        printf "%s%s%s%s%s%s" "$indent" "$COLOR_RED" "$BOX_V" "$COLOR_YELLOW" "$detail" "$COLOR_RESET"
        printf '%*s' "$padding" ''
        echo -e "${COLOR_RED}${BOX_V}${COLOR_RESET}"
    done
    
    # Bottom border
    echo -e "${indent}${COLOR_RED}${BOX_BL}${border}${BOX_BR}${COLOR_RESET}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Quick Help Display
# ═══════════════════════════════════════════════════════════════════════════════

show_quick_help() {
    local port="${1:-5000}"
    
    ui_init
    
    local indent
    printf -v indent '%*s' "$LAYOUT_INDENT" ''
    
    echo ""
    echo -e "${indent}${COLOR_GRAY}${ICON_BULLET}${COLOR_RESET} Press ${COLOR_MAGENTA}Q${COLOR_RESET} to quit  ${COLOR_GRAY}${ICON_BULLET}${COLOR_RESET} Dashboard: ${COLOR_CYAN}http://localhost:${port}${COLOR_RESET}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Uptime Formatting
# ═══════════════════════════════════════════════════════════════════════════════

format_uptime() {
    local seconds="$1"
    
    if (( seconds >= 3600 )); then
        local hours=$((seconds / 3600))
        local mins=$(((seconds % 3600) / 60))
        echo "${hours}h ${mins}m"
    elif (( seconds >= 60 )); then
        local mins=$((seconds / 60))
        local secs=$((seconds % 60))
        echo "${mins}m ${secs}s"
    else
        echo "${seconds}s"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Live Status Display
# ═══════════════════════════════════════════════════════════════════════════════

write_live_status() {
    local flask_ok="${1:-true}"
    local tunnel_ok="${2:-true}"
    
    ui_init
    
    local indent
    printf -v indent '%*s' "$LAYOUT_INDENT" ''
    
    local uptime="0s"
    if [[ -n "$STARTUP_TIME" ]]; then
        local now
        now=$(date +%s)
        local elapsed=$((now - STARTUP_TIME))
        uptime=$(format_uptime "$elapsed")
    fi
    
    local flask_status tunnel_status
    if [[ "$flask_ok" == "true" ]]; then
        flask_status="${COLOR_GREEN}${ICON_SUCCESS}${COLOR_RESET}"
    else
        flask_status="${COLOR_RED}${ICON_ERROR}${COLOR_RESET}"
    fi
    
    if [[ "$tunnel_ok" == "true" ]]; then
        tunnel_status="${COLOR_GREEN}${ICON_SUCCESS}${COLOR_RESET}"
    else
        tunnel_status="${COLOR_RED}${ICON_ERROR}${COLOR_RESET}"
    fi
    
    printf "\r%-${LAYOUT_SPINNER_PAD}s" ""
    printf "\r%s%sRunning %s | Flask: %s%s | Tunnel: %s%s | Press Q to quit%s" \
        "$indent" "$COLOR_GRAY" "$uptime" "$flask_status" "$COLOR_GRAY" "$tunnel_status" "$COLOR_GRAY" "$COLOR_RESET"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Interactive Wait Loop
# ═══════════════════════════════════════════════════════════════════════════════

# Wait for Q key or process exit
# Returns: "quit" if Q pressed, "exit" if process died
wait_for_quit() {
    local flask_pid="$1"
    local tunnel_pid="$2"
    local show_status="${3:-true}"
    
    local last_status_update=0
    
    # Configure terminal for non-blocking input
    local old_tty_settings=""
    if [[ -t 0 ]]; then
        old_tty_settings=$(stty -g 2>/dev/null || true)
        stty -echo -icanon min 0 time 1 2>/dev/null || true
    fi
    
    # Restore terminal on exit
    cleanup_terminal() {
        if [[ -n "$old_tty_settings" ]]; then
            stty "$old_tty_settings" 2>/dev/null || true
        fi
    }
    trap cleanup_terminal EXIT
    
    while true; do
        # Check for keypress
        if [[ -t 0 ]]; then
            local key=""
            read -r -n1 -t 0.1 key 2>/dev/null || true
            # Convert to lowercase (bash 3.2 compatible)
            local key_lower
            key_lower=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
            if [[ "$key_lower" == "q" ]]; then
                cleanup_terminal
                [[ "$show_status" == "true" ]] && clear_spinner_line
                echo "quit"
                return 0
            fi
        fi
        
        # Check if processes are still running
        local flask_ok="true"
        local tunnel_ok="true"
        
        if [[ -n "$flask_pid" ]] && ! kill -0 "$flask_pid" 2>/dev/null; then
            flask_ok="false"
        fi
        
        if [[ -n "$tunnel_pid" ]] && ! kill -0 "$tunnel_pid" 2>/dev/null; then
            tunnel_ok="false"
        fi
        
        if [[ "$flask_ok" == "false" ]]; then
            cleanup_terminal
            [[ "$show_status" == "true" ]] && clear_spinner_line
            echo ""
            write_status "Flask process died unexpectedly" "Error"
            echo "exit"
            return 1
        fi
        
        if [[ "$tunnel_ok" == "false" ]]; then
            cleanup_terminal
            [[ "$show_status" == "true" ]] && clear_spinner_line
            echo ""
            write_status "Cloudflared process died unexpectedly" "Error"
            echo "exit"
            return 1
        fi
        
        # Update status display every second
        if [[ "$show_status" == "true" ]]; then
            local now
            now=$(date +%s)
            if (( now - last_status_update >= 1 )); then
                write_live_status "$flask_ok" "$tunnel_ok"
                last_status_update=$now
            fi
        fi
        
        sleep 0.1
    done
}
