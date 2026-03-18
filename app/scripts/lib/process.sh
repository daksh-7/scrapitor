#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  process.sh - Process management for Scrapitor
# ═══════════════════════════════════════════════════════════════════════════════

# ── Managed Process Tracking ──────────────────────────────────────────────────
# Store PIDs in associative array (bash 4+) or simple variables (bash 3)
declare -g FLASK_PID=""
declare -g CLOUDFLARED_PID=""
declare -g FLASK_LOG_OUT=""
declare -g FLASK_LOG_ERR=""
declare -g CLOUDFLARED_LOG_OUT=""
declare -g CLOUDFLARED_LOG_ERR=""

# ═══════════════════════════════════════════════════════════════════════════════
#  Process Lifecycle
# ═══════════════════════════════════════════════════════════════════════════════

# Start a managed background process
# Usage: start_managed_process <name> <command> <args...>
# Sets: ${NAME}_PID variable
start_managed_process() {
    local name="$1"
    local log_out="$2"
    local log_err="$3"
    shift 3
    local cmd=("$@")
    
    # Clear log files
    if [[ -n "$log_out" ]]; then
        : > "$log_out" 2>/dev/null || true
    fi
    if [[ -n "$log_err" ]]; then
        : > "$log_err" 2>/dev/null || true
    fi
    
    # Start process in background
    if [[ -n "$log_out" ]] && [[ -n "$log_err" ]]; then
        "${cmd[@]}" > "$log_out" 2> "$log_err" &
    elif [[ -n "$log_out" ]]; then
        "${cmd[@]}" > "$log_out" 2>&1 &
    else
        "${cmd[@]}" &>/dev/null &
    fi
    
    local pid=$!
    
    # Store PID based on name
    case "$name" in
        flask)
            FLASK_PID=$pid
            FLASK_LOG_OUT="$log_out"
            FLASK_LOG_ERR="$log_err"
            ;;
        cloudflared)
            CLOUDFLARED_PID=$pid
            CLOUDFLARED_LOG_OUT="$log_out"
            CLOUDFLARED_LOG_ERR="$log_err"
            ;;
    esac
    
    echo "$pid"
}

# Stop a managed process gracefully
stop_managed_process() {
    local name="$1"
    local grace_period="${2:-3}"
    
    local pid=""
    case "$name" in
        flask) pid="$FLASK_PID" ;;
        cloudflared) pid="$CLOUDFLARED_PID" ;;
    esac
    
    if [[ -z "$pid" ]]; then
        return 0
    fi
    
    # Check if process is still running
    if ! kill -0 "$pid" 2>/dev/null; then
        # Already dead, clear PID
        case "$name" in
            flask) FLASK_PID="" ;;
            cloudflared) CLOUDFLARED_PID="" ;;
        esac
        return 0
    fi
    
    # Try graceful termination first (SIGTERM)
    kill -TERM "$pid" 2>/dev/null || true
    
    # Wait for process to exit
    local waited=0
    while (( waited < grace_period )); do
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 1
        ((waited++))
    done
    
    # Force kill if still running
    if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
    fi
    
    # Clear PID
    case "$name" in
        flask) FLASK_PID="" ;;
        cloudflared) CLOUDFLARED_PID="" ;;
    esac
    
    return 0
}

# Stop all managed processes
stop_all_managed_processes() {
    local grace_period="${1:-3}"
    
    stop_managed_process "flask" "$grace_period"
    stop_managed_process "cloudflared" "$grace_period"
}

# Check if a managed process is running
test_managed_process_running() {
    local name="$1"
    
    local pid=""
    case "$name" in
        flask) pid="$FLASK_PID" ;;
        cloudflared) pid="$CLOUDFLARED_PID" ;;
    esac
    
    if [[ -z "$pid" ]]; then
        return 1
    fi
    
    kill -0 "$pid" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Stale Process Cleanup
# ═══════════════════════════════════════════════════════════════════════════════

# Stop processes using a specific port
stop_processes_on_port() {
    local port="$1"
    local count=0
    
    # Method 1: lsof (most systems, including macOS)
    if command -v lsof &>/dev/null; then
        local pids
        pids=$(lsof -ti ":$port" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            for pid in $pids; do
                kill -TERM "$pid" 2>/dev/null && ((count++)) || true
            done
        fi
    # Method 2: fuser (some Linux systems)
    elif command -v fuser &>/dev/null; then
        fuser -k "$port/tcp" 2>/dev/null && ((count++)) || true
    # Method 3: ss + awk (fallback, portable - no grep -P)
    elif command -v ss &>/dev/null; then
        local pids
        # Extract PIDs using awk instead of grep -P (macOS compatible)
        pids=$(ss -tlnp "sport = :$port" 2>/dev/null | awk -F'pid=' '{print $2}' | awk -F',' '{print $1}' | grep -E '^[0-9]+$' || true)
        for pid in $pids; do
            kill -TERM "$pid" 2>/dev/null && ((count++)) || true
        done
    # Method 4: netstat (Termux/Android fallback)
    elif command -v netstat &>/dev/null; then
        local pids
        pids=$(netstat -tlnp 2>/dev/null | awk -v port=":$port" '$4 ~ port {split($7,a,"/"); print a[1]}' | grep -E '^[0-9]+$' || true)
        for pid in $pids; do
            kill -TERM "$pid" 2>/dev/null && ((count++)) || true
        done
    fi
    
    echo "$count"
}

# Stop stale cloudflared processes for our port
stop_stale_cloudflared() {
    local port="$1"
    local count=0
    
    if command -v pgrep &>/dev/null; then
        local pids
        # More specific pattern: cloudflared tunnel with our exact port
        pids=$(pgrep -f "cloudflared.*tunnel.*--url.*http://127\.0\.0\.1:${port}\b" 2>/dev/null || true)
        for pid in $pids; do
            kill -TERM "$pid" 2>/dev/null && ((count++)) || true
        done
    fi
    
    echo "$count"
}

# Stop stale Python processes running our app
stop_stale_flask() {
    local venv_python="$1"
    local count=0
    
    if command -v pgrep &>/dev/null; then
        # Look for python processes running app.server from our venv
        local pids
        if [[ -n "$venv_python" ]] && [[ -x "$venv_python" ]]; then
            # Try to match our specific venv python first
            local venv_pattern
            venv_pattern=$(printf '%s' "$venv_python" | sed 's/[.[\*^$()+?{|\\]/\\&/g')
            pids=$(pgrep -f "${venv_pattern}.*-m.*app\.server" 2>/dev/null || true)
        fi
        # Fallback to generic pattern if no matches or no venv specified
        if [[ -z "$pids" ]]; then
            pids=$(pgrep -f "\.venv/bin/python.*-m.*app\.server" 2>/dev/null || true)
        fi
        for pid in $pids; do
            kill -TERM "$pid" 2>/dev/null && ((count++)) || true
        done
    fi
    
    echo "$count"
}

# Stop all stale processes
stop_stale_processes() {
    local port="$1"
    local venv_python="$2"
    local pid_file="$3"
    
    local stopped_cf=0
    local stopped_flask=0
    local stopped_pid=0
    
    # Stop cloudflared instances
    stopped_cf=$(stop_stale_cloudflared "$port")
    
    # Stop Flask instances
    stopped_flask=$(stop_stale_flask "$venv_python")
    
    # Also try PIDs from previous run
    if [[ -f "$pid_file" ]]; then
        while IFS= read -r pid; do
            if [[ "$pid" =~ ^[0-9]+$ ]]; then
                if kill -TERM "$pid" 2>/dev/null; then
                    ((stopped_pid++))
                fi
            fi
        done < "$pid_file"
        rm -f "$pid_file" 2>/dev/null || true
    fi
    
    local total=$((stopped_cf + stopped_flask + stopped_pid))
    if (( total > 0 )); then
        sleep 0.5
    fi
    
    echo "$total"
}

list_port_listeners() {
    local port="$1"
    local exclude_pid="${2:-}"

    if command -v lsof &>/dev/null; then
        lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | tail -n +2 | while read -r cmd pid _ _ _ _ _ _ addr _; do
            [[ -n "$exclude_pid" && "$pid" == "$exclude_pid" ]] && continue
            printf '%s\t%s\t%s\n' "$addr" "$pid" "$cmd"
        done
        return 0
    fi

    if command -v ss &>/dev/null; then
        ss -ltnp "sport = :$port" 2>/dev/null | tail -n +2 | while read -r _ _ _ addr _ rest; do
            local pid
            pid=$(printf '%s' "$rest" | awk -F'pid=' '{print $2}' | awk -F',' '{print $1}')
            local cmd
            cmd=$(printf '%s' "$rest" | awk -F'"' '{print $2}')
            [[ -z "$pid" ]] && continue
            [[ -n "$exclude_pid" && "$pid" == "$exclude_pid" ]] && continue
            printf '%s\t%s\t%s\n' "$addr" "$pid" "${cmd:-unknown}"
        done
    fi
}

resolve_available_port() {
    local preferred_port="$1"
    local python_exe="$2"
    local scan_count="${3:-100}"

    "$python_exe" - "$preferred_port" "$scan_count" <<'PY'
import socket
import sys

preferred = int(sys.argv[1])
scan_count = max(1, int(sys.argv[2]))
scan_end = min(65535, preferred + scan_count - 1)

def can_bind(port: int) -> bool:
    for host in ("127.0.0.1", "0.0.0.0"):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.bind((host, port))
        except OSError:
            return False
        finally:
            sock.close()
    return True

for port in range(preferred, scan_end + 1):
    if can_bind(port):
        print(port)
        raise SystemExit(0)

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.bind(("0.0.0.0", 0))
print(sock.getsockname()[1])
sock.close()
PY
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Health Checks
# ═══════════════════════════════════════════════════════════════════════════════

# Wait for a health endpoint to respond
# Returns 0 on success, 1 on timeout/failure
wait_for_health() {
    local port="$1"
    local timeout_seconds="${2:-30}"
    local process_pid="${3:-}"
    
    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + timeout_seconds))
    
    while (( $(date +%s) < end_time )); do
        # Check if process died
        if [[ -n "$process_pid" ]] && ! kill -0 "$process_pid" 2>/dev/null; then
            return 1
        fi
        
        # Try health endpoint
        for host in "127.0.0.1" "localhost"; do
            local payload=""
            if payload=$(curl -s -f --connect-timeout 2 --max-time 2 "http://${host}:${port}/health" 2>/dev/null); then
                if printf '%s' "$payload" | grep -Eq "\"status\"[[:space:]]*:[[:space:]]*\"healthy\"" &&
                   printf '%s' "$payload" | grep -Eq "\"port\"[[:space:]]*:[[:space:]]*${port}([[:space:]]*[,}])"; then
                    return 0
                fi
            fi
        done
        
        sleep 0.5
    done
    
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
#  PID File Management
# ═══════════════════════════════════════════════════════════════════════════════

save_pid_file() {
    local path="$1"
    shift
    local pids=("$@")
    
    printf '%s\n' "${pids[@]}" > "$path" 2>/dev/null || return 1
    return 0
}

remove_pid_file() {
    local path="$1"
    rm -f "$path" 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
#  Log File Utilities
# ═══════════════════════════════════════════════════════════════════════════════

get_log_content() {
    local path="$1"
    local tail_lines="${2:-20}"
    
    if [[ ! -f "$path" ]]; then
        return 1
    fi
    
    tail -n "$tail_lines" "$path" 2>/dev/null || true
}
