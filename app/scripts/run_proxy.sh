#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  Scrapitor Local Proxy - Start Flask server with Cloudflare tunnel
# ═══════════════════════════════════════════════════════════════════════════════
#
#  Launches the Scrapitor proxy server and establishes a Cloudflare tunnel
#  for external access. Press Q to quit gracefully.
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ══════════════════════════════════════════════════════════════════════════════
#  Bootstrap
# ══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$APP_ROOT")"
cd "$REPO_ROOT"

# Import modules
MODULES_DIR="${SCRIPT_DIR}/lib"
# shellcheck source=lib/ui.sh
source "${MODULES_DIR}/ui.sh"
# shellcheck source=lib/config.sh
source "${MODULES_DIR}/config.sh"
# shellcheck source=lib/python.sh
source "${MODULES_DIR}/python.sh"
# shellcheck source=lib/process.sh
source "${MODULES_DIR}/process.sh"
# shellcheck source=lib/tunnel.sh
source "${MODULES_DIR}/tunnel.sh"

# ══════════════════════════════════════════════════════════════════════════════
#  Dependency Checks
# ══════════════════════════════════════════════════════════════════════════════

# Check for required dependencies early
if ! command -v curl &>/dev/null; then
    echo ""
    echo "  ERROR: curl is required but not installed."
    echo ""
    echo "  Install it with:"
    echo "    Ubuntu/Debian: sudo apt install curl"
    echo "    Fedora/RHEL:   sudo dnf install curl"
    echo "    macOS:         brew install curl"
    echo "    Termux:        pkg install curl"
    echo ""
    exit 1
fi

# Detect Termux and show helpful hint
if [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux" ]]; then
    # Check if wake-lock is active
    if command -v termux-wake-lock &>/dev/null; then
        if ! pgrep -f "termux-wake-lock" &>/dev/null 2>&1; then
            echo ""
            echo "  TIP: Run 'termux-wake-lock' in another session to prevent Android"
            echo "       from killing this process when the screen is off."
            echo ""
        fi
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
#  Configuration
# ══════════════════════════════════════════════════════════════════════════════

get_scrapitor_config "$APP_ROOT" "$REPO_ROOT"
init_directories
set_runtime_environment

# ══════════════════════════════════════════════════════════════════════════════
#  Cleanup Handler
# ══════════════════════════════════════════════════════════════════════════════

cleanup() {
    echo ""
    write_subtle "Shutting down..."
    stop_all_managed_processes 3
    # Guard against uninitialized variables from early signals
    [[ -n "${CONFIG_PID_FILE:-}" ]] && remove_pid_file "$CONFIG_PID_FILE"
    [[ -n "${CONFIG_TUNNEL_URL_FILE:-}" ]] && rm -f "$CONFIG_TUNNEL_URL_FILE" 2>/dev/null || true
    write_status "Stopped" "Success"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# ══════════════════════════════════════════════════════════════════════════════
#  Main Flow
# ══════════════════════════════════════════════════════════════════════════════

main() {
    # Show banner
    show_banner
    
    # ── Python Setup ──────────────────────────────────────────────────────────
    if ! find_usable_python "$CONFIG_VENV_PYTHON"; then
        show_error_box "Python Not Found" \
            "Python 3.10+ is required but was not found." \
            "" \
            "Install Python from your package manager:" \
            "  Ubuntu/Debian: sudo apt install python3" \
            "  Fedora/RHEL:   sudo dnf install python3" \
            "  macOS:         brew install python3" \
            "" \
            "Or download from: https://www.python.org/downloads/"
        exit 1
    fi
    
    write_status "Python ${PYTHON_VERSION} found" "Success"
    
    # Create venv if needed
    local venv_created=false
    if ! test_venv_exists "$CONFIG_VENV_PATH"; then
        write_spinner "Creating virtual environment..."
        local venv_output
        venv_output=$(create_python_venv "$CONFIG_VENV_PATH" "$PYTHON_PATH" 2>&1)
        local venv_exit=$?
        
        if [[ $venv_exit -ne 0 ]]; then
            clear_spinner_line
            local install_hint
            install_hint=$(get_venv_install_hint "$PYTHON_PATH")
            show_error_box "Venv Creation Failed" \
                "Could not create virtual environment." \
                "" \
                "The Python venv module is missing. Install it:" \
                "  ${install_hint}" \
                "" \
                "Then re-run this script."
            exit 1
        fi
        clear_spinner_line
        write_status "Virtual environment created" "Success"
        venv_created=true
    fi
    
    # Install dependencies
    local requirements_path="${APP_ROOT}/requirements.txt"
    write_spinner "Checking dependencies..."
    
    local upgrade_pip="false"
    [[ "$venv_created" == "true" ]] && upgrade_pip="true"
    
    if ! install_python_dependencies "$CONFIG_VENV_PYTHON" "$requirements_path" "$upgrade_pip"; then
        clear_spinner_line
        show_error_box "Dependency Installation Failed" \
            "Could not install Python packages." \
            "" \
            "$DEP_ERROR"
        exit 1
    fi
    clear_spinner_line
    
    if (( DEP_INSTALLED_PACKAGES > 0 )); then
        write_status "Installed ${DEP_INSTALLED_PACKAGES} packages" "Success"
    else
        write_status "Dependencies up to date" "Success"
    fi
    
    # ── Cloudflared Setup ─────────────────────────────────────────────────────
    if ! find_cloudflared "$SCRIPT_DIR"; then
        if [[ "$CONFIG_AUTO_INSTALL" == "true" ]]; then
            write_spinner "Installing cloudflared..."
            if install_cloudflared "$SCRIPT_DIR"; then
                clear_spinner_line
                write_status "Cloudflared installed via ${CLOUDFLARED_SOURCE}" "Success"
            else
                clear_spinner_line
                # Show platform-specific install instructions
                if is_termux; then
                    show_error_box "Cloudflared Installation Failed" \
                        "Could not install cloudflared automatically." \
                        "" \
                        "Install manually in Termux:" \
                        "  pkg install cloudflared" \
                        "" \
                        "Then re-run this script."
                else
                    show_error_box "Cloudflared Installation Failed" \
                        "Could not install cloudflared automatically." \
                        "" \
                        "Manual install options:" \
                        "  macOS:   brew install cloudflared" \
                        "  Ubuntu:  Download from GitHub releases" \
                        "" \
                        "https://github.com/cloudflare/cloudflared/releases"
                fi
                exit 1
            fi
        else
            show_error_box "Cloudflared Not Found" \
                "cloudflared is required but not installed." \
                "" \
                "Install with: brew install cloudflared" \
                "Or download from GitHub releases"
            exit 1
        fi
    else
        write_status "Cloudflared ready" "Success"
    fi
    
    # ── Frontend Build ────────────────────────────────────────────────────────
    local spa_index="${CONFIG_SPA_DIST_DIR}/index.html"
    local frontend_src="${CONFIG_FRONTEND_DIR}/src"
    local needs_build=false
    
    if [[ ! -f "$spa_index" ]]; then
        needs_build=true
    elif [[ -d "$frontend_src" ]]; then
        # Check if any source file is newer than the built index
        local newest_src
        newest_src=$(find "$frontend_src" -type f -newer "$spa_index" 2>/dev/null | head -n1)
        if [[ -n "$newest_src" ]]; then
            needs_build=true
        fi
    fi
    
    if [[ "$needs_build" == "true" ]] && command -v npm &>/dev/null; then
        local node_modules="${CONFIG_FRONTEND_DIR}/node_modules"
        
        pushd "$CONFIG_FRONTEND_DIR" > /dev/null
        
        if [[ ! -d "$node_modules" ]]; then
            write_spinner "Installing frontend dependencies..."
            npm install --silent 2>/dev/null || true
            clear_spinner_line
        fi
        
        write_spinner "Building frontend..."
        if npm run build &>/dev/null; then
            clear_spinner_line
            write_status "Frontend built" "Success"
        else
            clear_spinner_line
            write_status "Frontend build failed (non-critical)" "Warning"
        fi
        
        popd > /dev/null
    fi
    
    # ── Stop Stale Processes ──────────────────────────────────────────────────
    stop_stale_processes "$CONFIG_PORT" "$CONFIG_VENV_PYTHON" "$CONFIG_PID_FILE" > /dev/null

    local requested_port="$CONFIG_PORT"
    local selected_port=""
    selected_port=$(resolve_available_port "$requested_port" "$PYTHON_PATH")

    if [[ -z "$selected_port" ]]; then
        show_error_box "Port Selection Failed" \
            "Could not find an available TCP port to start Scrapitor."
        exit 1
    fi

    if [[ "$selected_port" != "$requested_port" ]]; then
        CONFIG_PORT="$selected_port"
        export PROXY_PORT="$CONFIG_PORT"

        write_status "Port ${requested_port} in use, using :${CONFIG_PORT}" "Warning"
    fi
    
    # ── Start Flask ───────────────────────────────────────────────────────────
    write_section "Starting Services"
    
    local flask_out="${CONFIG_LOGS_DIR}/flask.stdout.log"
    local flask_err="${CONFIG_LOGS_DIR}/flask.stderr.log"
    
    local flask_pid
    flask_pid=$(start_managed_process "flask" "$flask_out" "$flask_err" \
        "$CONFIG_VENV_PYTHON" -m app.server)
    
    # Wait for health with spinner
    local health_start
    health_start=$(date +%s)
    local health_ok=false
    
    while (( $(date +%s) - health_start < CONFIG_HEALTH_TIMEOUT )); do
        write_spinner "Flask starting on port ${CONFIG_PORT}..."
        sleep 0.3
        
        # Check if process died
        if ! kill -0 "$flask_pid" 2>/dev/null; then
            clear_spinner_line
            show_error_box "Flask Failed to Start" \
                "The server exited unexpectedly." \
                "" \
                "Check logs: ${flask_err}"
            exit 1
        fi
        
        # Check health
        if curl -s -f --connect-timeout 1 --max-time 1 "http://127.0.0.1:${CONFIG_PORT}/health" &>/dev/null; then
            health_ok=true
            break
        fi
    done
    clear_spinner_line
    
    if [[ "$health_ok" != "true" ]]; then
        local -a port_conflicts=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && port_conflicts+=("$line")
        done < <(list_port_listeners "$CONFIG_PORT" "$flask_pid")

        local -a details=(
            "Server did not respond within ${CONFIG_HEALTH_TIMEOUT} seconds."
            ""
            "Port ${CONFIG_PORT} may be in use."
        )

        local shown=0
        local entry=""
        for entry in "${port_conflicts[@]}"; do
            IFS=$'\t' read -r addr pid cmd <<< "$entry"
            details+=("[${addr}] PID ${pid} - ${cmd}")
            ((shown += 1))
            if (( shown >= 3 )); then
                break
            fi
        done

        show_error_box "Flask Health Check Failed" "${details[@]}"
        stop_all_managed_processes
        exit 1
    fi
    
    write_status "Flask healthy on :${CONFIG_PORT}" "Success"
    
    # ── Start Tunnel ──────────────────────────────────────────────────────────
    local tunnel_out="${CONFIG_LOGS_DIR}/cloudflared.stdout.log"
    local tunnel_err="${CONFIG_LOGS_DIR}/cloudflared.stderr.log"
    
    # Build cloudflared args as an array for proper handling
    local -a cf_args_array
    cf_args_array=("tunnel" "--no-autoupdate")
    
    if [[ -n "${CLOUDFLARED_FLAGS:-}" ]]; then
        # Split custom flags by whitespace into array
        read -ra extra_args <<< "${CLOUDFLARED_FLAGS}"
        cf_args_array+=("${extra_args[@]}")
    else
        # Fast defaults
        cf_args_array+=("--edge-ip-version" "4" "--loglevel" "info")
    fi
    cf_args_array+=("--url" "http://127.0.0.1:${CONFIG_PORT}")
    
    local max_attempts=2
    local tunnel_url=""
    
    for (( attempt=1; attempt<=max_attempts; attempt++ )); do
        if (( attempt > 1 )); then
            write_subtle "Retrying tunnel (attempt ${attempt}/${max_attempts})..."
        fi
        
        # Start cloudflared with proper array expansion
        local cf_pid
        cf_pid=$(start_managed_process "cloudflared" "$tunnel_out" "$tunnel_err" \
            "$CLOUDFLARED_PATH" "${cf_args_array[@]}")
        
        # Wait for URL with spinner
        local url_start
        url_start=$(date +%s)
        
        while (( $(date +%s) - url_start < CONFIG_TUNNEL_TIMEOUT )); do
            local elapsed=$(( $(date +%s) - url_start ))
            write_spinner "Establishing tunnel... ${elapsed}s"
            sleep 0.2
            
            # Check if process died
            if ! kill -0 "$cf_pid" 2>/dev/null; then
                break
            fi
            
            # Check for URL
            if wait_for_tunnel_url "$tunnel_out" "$tunnel_err" 1 "$cf_pid"; then
                tunnel_url="$TUNNEL_URL"
                break
            fi
        done
        clear_spinner_line
        
        if [[ -n "$tunnel_url" ]]; then
            break
        fi
        
        # Clean up failed attempt
        stop_managed_process "cloudflared" 1
    done
    
    if [[ -z "$tunnel_url" ]]; then
        show_error_box "Tunnel Failed" \
            "Could not establish Cloudflare tunnel." \
            "" \
            "Check your internet connection." \
            "Logs: ${tunnel_err}"
        stop_all_managed_processes
        exit 1
    fi
    
    write_status "Tunnel ready" "Success"
    
    # ── Success! ──────────────────────────────────────────────────────────────
    save_tunnel_url "$CONFIG_TUNNEL_URL_FILE" "$tunnel_url"
    save_pid_file "$CONFIG_PID_FILE" "$FLASK_PID" "$CLOUDFLARED_PID"
    
    show_url_box "$tunnel_url" "$CONFIG_PORT"
    show_quick_help "$CONFIG_PORT"
    
    # ── Main Loop ─────────────────────────────────────────────────────────────
    wait_for_quit "$FLASK_PID" "$CLOUDFLARED_PID" "true"
}

# ══════════════════════════════════════════════════════════════════════════════
#  Entry Point
# ══════════════════════════════════════════════════════════════════════════════

main "$@"
