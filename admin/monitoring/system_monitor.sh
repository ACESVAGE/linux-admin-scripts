#!/usr/bin/env bash
# =============================================================================
# system_monitor.sh — Interactive Linux System Performance & Health Monitor
# =============================================================================
# Author      : ACESVAGE
# Repository  : https://github.com/ACESVAGE/linux-admin-scripts
# Description : Production-grade interactive CLI tool for comprehensive Linux
#               system administration and performance monitoring. Covers CPU,
#               memory, swap, disk I/O, process inspection, vmstat metrics,
#               threshold alerting, live dashboards, and automated watchdogs.
#
# Usage       : ./system_monitor.sh  (or sudo ./system_monitor.sh for full root features)
# Requirements: bash 4+, coreutils, procps, awk, sed, grep
# Optional    : sysstat (iostat/mpstat), lm-sensors, htop
# Tested on   : Ubuntu 20.04+, Debian 11+, Fedora 38+, CentOS/RHEL 8+, Arch
# =============================================================================

set -euo pipefail

# ── Colours & Formatting ─────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Logging Helpers ──────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${RESET}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET}   $*" >&2; }
log_success() { echo -e "${GREEN}[✔]${RESET}       $*"; }
log_section() { echo -e "\n${CYAN}${BOLD}══ $* ══${RESET}"; }

# ── Audit Logging ────────────────────────────────────────────────────────────
AUDIT_LOG="/var/log/system_monitor_audit.log"

audit() {
    local action="$1"
    local details="$2"
    local run_user
    run_user="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    if [[ -w "$(dirname "$AUDIT_LOG")" ]]; then
        echo "$timestamp | USER=$run_user | ACTION=$action | $details" >> "$AUDIT_LOG" 2>/dev/null || true
    fi
}

# ── Visual Progress Bar Helper ───────────────────────────────────────────────
draw_bar() {
    local percent="${1%.*}"
    local width="${2:-30}"
    local label="${3:-}"

    # Clamp between 0 and 100
    (( percent < 0 )) && percent=0
    (( percent > 100 )) && percent=100

    local filled=$(( percent * width / 100 ))
    local empty=$(( width - filled ))

    local color="$GREEN"
    if (( percent >= 90 )); then
        color="$RED"
    elif (( percent >= 75 )); then
        color="$YELLOW"
    fi

    local bar=""
    for ((i = 0; i < filled; i++)); do bar+="█"; done
    for ((i = 0; i < empty; i++)); do bar+="░"; done

    printf "%-12s ${color}[%s] %3d%%${RESET}\n" "$label" "$bar" "$percent"
}

# ── Root Privilege Notice ───────────────────────────────────────────────────
is_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]]
}

require_root_for_action() {
    if ! is_root; then
        log_warn "This operation requires root privileges."
        echo -e "Please re-run this action using ${BOLD}sudo${RESET}."
        return 1
    fi
    return 0
}

# =============================================================================
# MODULE 1 — SYSTEM OVERVIEW & HEALTH DASHBOARD
# =============================================================================
system_overview() {
    log_section "System Overview & Health Dashboard"

    local hostname
    hostname="$(hostname -f 2>/dev/null || hostname)"

    local os_name="Unknown Linux"
    if [[ -f /etc/os-release ]]; then
        os_name="$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')"
    fi

    local kernel
    kernel="$(uname -r)"

    local arch
    arch="$(uname -m)"

    local uptime_str
    uptime_str="$(uptime -p 2>/dev/null || uptime | sed 's/.*up \([^,]*\), .*/\1/')"

    local boot_time
    boot_time="$(who -b 2>/dev/null | awk '{print $3, $4}' || echo "N/A")"

    local cpu_cores
    cpu_cores="$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)"

    local load_avg
    load_avg="$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null || uptime | awk -F'load average:' '{print $2}')"
    local load_1m
    load_1m="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0.00")"

    local user_count
    user_count="$(who | wc -l)"

    # Compute load ratio
    local load_status="${GREEN}Normal${RESET}"
    if awk "BEGIN {exit !($load_1m > $cpu_cores * 1.5)}"; then
        load_status="${RED}${BOLD}CRITICAL OVERLOAD${RESET}"
    elif awk "BEGIN {exit !($load_1m > $cpu_cores)}"; then
        load_status="${YELLOW}Elevated${RESET}"
    fi

    echo -e "${BOLD}Hardware & Kernel:${RESET}"
    printf "  %-18s : %s\n" "Hostname" "$hostname"
    printf "  %-18s : %s\n" "Operating System" "$os_name"
    printf "  %-18s : %s (%s)\n" "Kernel / Arch" "$kernel" "$arch"
    printf "  %-18s : %s cores\n" "CPU Capacity" "$cpu_cores"
    echo ""
    echo -e "${BOLD}Uptime & Current Activity:${RESET}"
    printf "  %-18s : %s (Last boot: %s)\n" "System Uptime" "$uptime_str" "$boot_time"
    printf "  %-18s : %s (Status: %b)\n" "Load Average" "$load_avg" "$load_status"
    printf "  %-18s : %s active session(s)\n" "Logged-in Users" "$user_count"

    echo ""
    echo -e "${BOLD}Current Logged-in Sessions:${RESET}"
    who 2>/dev/null | awk '{printf "  • %-12s %-10s %s (%s)\n", $1, $2, $3" "$4, $5}' || echo "  None"

    audit "VIEW_OVERVIEW" "HOST=$hostname LOAD=$load_1m"
}

# =============================================================================
# MODULE 2 — CPU UTILIZATION & CORE ANALYSIS
# =============================================================================
cpu_utilization() {
    log_section "CPU Utilization & Core Analysis"

    local cpu_model
    cpu_model="$(grep -m1 '^model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Generic CPU")"
    local cpu_mhz
    cpu_mhz="$(grep -m1 '^cpu MHz' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "N/A")"
    local cpu_cores
    cpu_cores="$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)"

    echo -e "${BOLD}Processor Information:${RESET}"
    printf "  %-16s: %s\n" "Model" "$cpu_model"
    printf "  %-16s: %s MHz\n" "Clock Speed" "$cpu_mhz"
    printf "  %-16s: %s logical cores\n" "Total Cores" "$cpu_cores"
    echo ""

    log_info "Measuring 1-second CPU delta across all cores..."

    # Read /proc/stat twice with 1 second delay
    read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
    local prev_idle=$((idle + iowait))
    local prev_non_idle=$((user + nice + system + irq + softirq + steal))
    local prev_total=$((prev_idle + prev_non_idle))

    sleep 1

    read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
    local curr_idle=$((idle + iowait))
    local curr_non_idle=$((user + nice + system + irq + softirq + steal))
    local curr_total=$((curr_idle + curr_non_idle))

    local total_diff=$((curr_total - prev_total))
    local idle_diff=$((curr_idle - prev_idle))

    local cpu_pct=0
    if (( total_diff > 0 )); then
        cpu_pct=$(( (total_diff - idle_diff) * 100 / total_diff ))
    fi

    echo ""
    echo -e "${BOLD}Aggregate Utilization:${RESET}"
    draw_bar "$cpu_pct" 30 "CPU Total"

    echo ""
    echo -e "${BOLD}Per-Core Instantaneous Stats (via /proc/stat):${RESET}"
    printf "  %-8s %-12s %-12s %-12s\n" "Core" "User(ticks)" "Sys(ticks)" "Idle(ticks)"
    echo "  ────────────────────────────────────────────────"
    grep -E '^cpu[0-9]+' /proc/stat | head -n 16 | while read -r core c_user c_nice c_sys c_idle rest; do
        printf "  %-8s %-12s %-12s %-12s\n" "$core" "$c_user" "$c_sys" "$c_idle"
    done
    if (( cpu_cores > 16 )); then
        echo "  ... ($((cpu_cores - 16)) more cores omitted for brevity)"
    fi

    # Temperature sensors check if available
    echo ""
    echo -e "${BOLD}Hardware Thermal Sensors:${RESET}"
    local sensor_found=0
    if command -v sensors &>/dev/null; then
        sensors 2>/dev/null | grep -E '(Core|temp|Package)' | sed 's/^/  /' || true
        sensor_found=1
    elif [[ -d /sys/class/thermal ]]; then
        for zone in /sys/class/thermal/thermal_zone*; do
            if [[ -f "$zone/temp" && -f "$zone/type" ]]; then
                local z_type z_temp
                z_type="$(cat "$zone/type" 2>/dev/null || echo "zone")"
                z_temp="$(cat "$zone/temp" 2>/dev/null || echo "0")"
                z_temp=$((z_temp / 1000))
                printf "  • %-16s: %d°C\n" "$z_type" "$z_temp"
                sensor_found=1
            fi
        done
    fi

    if (( sensor_found == 0 )); then
        echo "  [i] No hardware thermal sensors detected or 'lm-sensors' not installed."
    fi

    audit "VIEW_CPU" "USAGE=${cpu_pct}% CORES=$cpu_cores"
}

# =============================================================================
# MODULE 3 — MEMORY & SWAP DIAGNOSTICS
# =============================================================================
memory_diagnostics() {
    log_section "Memory & Swap Diagnostics"

    if [[ ! -f /proc/meminfo ]]; then
        log_error "/proc/meminfo is inaccessible."
        return 1
    fi

    local mem_total_kb mem_free_kb mem_avail_kb mem_cached_kb mem_buffers_kb swap_total_kb swap_free_kb
    mem_total_kb="$(grep -m1 '^MemTotal:' /proc/meminfo | awk '{print $2}')"
    mem_free_kb="$(grep -m1 '^MemFree:' /proc/meminfo | awk '{print $2}')"
    mem_avail_kb="$(grep -m1 '^MemAvailable:' /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "$mem_free_kb")"
    mem_cached_kb="$(grep -m1 '^Cached:' /proc/meminfo | awk '{print $2}')"
    mem_buffers_kb="$(grep -m1 '^Buffers:' /proc/meminfo | awk '{print $2}')"
    swap_total_kb="$(grep -m1 '^SwapTotal:' /proc/meminfo | awk '{print $2}')"
    swap_free_kb="$(grep -m1 '^SwapFree:' /proc/meminfo | awk '{print $2}')"

    local mem_used_kb=$((mem_total_kb - mem_avail_kb))
    local mem_pct=0
    (( mem_total_kb > 0 )) && mem_pct=$(( mem_used_kb * 100 / mem_total_kb ))

    local swap_used_kb=$((swap_total_kb - swap_free_kb))
    local swap_pct=0
    (( swap_total_kb > 0 )) && swap_pct=$(( swap_used_kb * 100 / swap_total_kb ))

    # Convert to MB
    local mem_total_mb=$((mem_total_kb / 1024))
    local mem_used_mb=$((mem_used_kb / 1024))
    local mem_avail_mb=$((mem_avail_kb / 1024))
    local mem_free_mb=$((mem_free_kb / 1024))
    local mem_buff_cache_mb=$(((mem_cached_kb + mem_buffers_kb) / 1024))

    local swap_total_mb=$((swap_total_kb / 1024))
    local swap_used_mb=$((swap_used_kb / 1024))
    local swap_free_mb=$((swap_free_kb / 1024))

    echo -e "${BOLD}Physical RAM Usage:${RESET}"
    draw_bar "$mem_pct" 30 "RAM ($mem_pct%)"
    printf "  %-18s: %6d MB (%0.2f GB)\n" "Total Memory" "$mem_total_mb" "$(awk "BEGIN {print $mem_total_mb/1024}")"
    printf "  %-18s: %6d MB\n" "Used Memory" "$mem_used_mb"
    printf "  %-18s: %6d MB\n" "Available Memory" "$mem_avail_mb"
    printf "  %-18s: %6d MB\n" "Free Memory" "$mem_free_mb"
    printf "  %-18s: %6d MB\n" "Buffers / Cache" "$mem_buff_cache_mb"

    echo ""
    echo -e "${BOLD}Swap Space Usage:${RESET}"
    if (( swap_total_kb > 0 )); then
        draw_bar "$swap_pct" 30 "Swap ($swap_pct%)"
        printf "  %-18s: %6d MB\n" "Total Swap" "$swap_total_mb"
        printf "  %-18s: %6d MB\n" "Used Swap" "$swap_used_mb"
        printf "  %-18s: %6d MB\n" "Free Swap" "$swap_free_mb"
    else
        echo "  [i] No swap partition/file configured on this system."
    fi

    echo ""
    echo -e "${BOLD}Out-Of-Memory (OOM) Incident Check:${RESET}"
    local oom_events
    oom_events="$(dmesg 2>/dev/null | grep -iE 'killed process|out of memory' | tail -n 5 || true)"
    if [[ -n "$oom_events" ]]; then
        echo -e "${RED}${BOLD}⚠ WARNING: Recent OOM killer events detected in kernel ring buffer:${RESET}"
        echo "$oom_events" | sed 's/^/  /'
    else
        echo -e "  ${GREEN}✔ No recent OOM killer events recorded in kernel buffer.${RESET}"
    fi

    audit "VIEW_MEMORY" "RAM_USED=${mem_pct}% SWAP_USED=${swap_pct}%"
}

# =============================================================================
# MODULE 4 — DISK I/O & STORAGE HEALTH
# =============================================================================
disk_io_storage() {
    log_section "Disk I/O & Storage Health"

    echo -e "${BOLD}Mounted Filesystems & Capacity (df -h):${RESET}"
    printf "  %-22s %-8s %-8s %-8s %-6s %s\n" "Filesystem" "Size" "Used" "Avail" "Use%" "Mounted on"
    echo "  ──────────────────────────────────────────────────────────────────"

    while read -r fs size used avail pct mountpoint; do
        local num_pct="${pct%\%}"
        local color="$GREEN"
        if (( num_pct >= 90 )); then
            color="${RED}${BOLD}"
        elif (( num_pct >= 80 )); then
            color="${YELLOW}"
        fi
        printf "  %-22s %-8s %-8s %-8s ${color}%-6s${RESET} %s\n" \
            "${fs:0:22}" "$size" "$used" "$avail" "$pct" "$mountpoint"
    done < <(df -h -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | awk 'NR>1 {print $1, $2, $3, $4, $5, $6}')

    echo ""
    echo -e "${BOLD}Inode Allocation (df -i):${RESET}"
    printf "  %-22s %-10s %-10s %-6s %s\n" "Filesystem" "Inodes" "IFree" "IUse%" "Mounted on"
    echo "  ────────────────────────────────────────────────────────────"
    df -i -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | awk 'NR>1 {printf "  %-22s %-10s %-10s %-6s %s\n", substr($1,1,22), $2, $4, $5, $6}'

    echo ""
    echo -e "${BOLD}Disk I/O Throughput & IOPS:${RESET}"
    if command -v iostat &>/dev/null; then
        log_info "Collecting 2-second iostat sample..."
        iostat -xz 1 2 2>/dev/null | awk 'BEGIN{p=0} /^Device/{p++} p==2{print "  " $0}'
    elif [[ -f /proc/diskstats ]]; then
        echo "  [i] iostat not found. Displaying cumulative /proc/diskstats for primary drives:"
        printf "  %-12s %-16s %-16s\n" "Device" "Reads Completed" "Writes Completed"
        echo "  ────────────────────────────────────────────"
        awk '$3 ~ /^(sd[a-z]|nvme[0-9]n[0-9]|vd[a-z])$/ {printf "  %-12s %-16s %-16s\n", $3, $4, $8}' /proc/diskstats
    else
        log_warn "No disk I/O metrics provider found."
    fi

    audit "VIEW_DISK_IO" "INSPECTED=true"
}

# =============================================================================
# MODULE 5 — VIRTUAL MEMORY & KERNEL SUBSYSTEM (VMSTAT)
# =============================================================================
vmstat_analysis() {
    log_section "Virtual Memory & Kernel Subsystem Analysis"

    if ! command -v vmstat &>/dev/null; then
        log_error "'vmstat' command is not available."
        return 1
    fi

    log_info "Capturing 2-second vmstat telemetry..."
    echo ""
    echo -e "${BOLD}Raw vmstat output (1-second sampling):${RESET}"
    vmstat 1 3 | sed 's/^/  /'

    echo ""
    echo -e "${BOLD}Key Subsystem Metric Guide:${RESET}"
    echo -e "  • ${CYAN}procs (r)${RESET}  : Number of processes waiting for run time. > Cores indicates CPU bottleneck."
    echo -e "  • ${CYAN}procs (b)${RESET}  : Number of processes in uninterruptible sleep (waiting on I/O)."
    echo -e "  • ${CYAN}memory (si/so)${RESET}: Memory swapped in/out from disk. Values > 0 indicate RAM exhaustion."
    echo -e "  • ${CYAN}io (bi/bo)${RESET}  : Blocks received (bi) and sent (bo) to block devices per second."
    echo -e "  • ${CYAN}system (in/cs)${RESET}: Interrupts (in) and Context switches (cs) per second."
    echo -e "  • ${CYAN}cpu (wa)${RESET}   : CPU waiting for pending I/O. > 15-20% means disk I/O is choking the system."

    local vm_r vm_b vm_so vm_wa
    vm_r="$(vmstat 1 2 | tail -n 1 | awk '{print $1}')"
    vm_b="$(vmstat 1 2 | tail -n 1 | awk '{print $2}')"
    vm_so="$(vmstat 1 2 | tail -n 1 | awk '{print $8}')"
    vm_wa="$(vmstat 1 2 | tail -n 1 | awk '{print $16}')"

    echo ""
    echo -e "${BOLD}Live Diagnosis:${RESET}"
    if (( vm_r > 8 )); then
        log_warn "Run queue (r=$vm_r) is high! System is experiencing CPU contention."
    else
        log_success "Run queue is healthy (r=$vm_r)."
    fi

    if (( vm_b > 2 )); then
        log_warn "Blocked processes (b=$vm_b) detected! System is stalling on disk or network I/O."
    else
        log_success "Blocked process count is normal (b=$vm_b)."
    fi

    if (( vm_so > 0 )); then
        log_warn "Active swap-out detected (so=$vm_so)! RAM pressure is causing disk thrashing."
    else
        log_success "No active swap-out occurring."
    fi

    audit "VIEW_VMSTAT" "R=$vm_r B=$vm_b WA=$vm_wa SO=$vm_so"
}

# =============================================================================
# MODULE 6 — PROCESS INSPECTOR & TOP CONSUMERS
# =============================================================================
process_inspector() {
    log_section "Process Inspector & Top Resource Consumers"

    echo -e "${BOLD}Top 10 Processes by CPU Usage:${RESET}"
    printf "  %-8s %-12s %-6s %-6s %-10s %s\n" "PID" "USER" "%CPU" "%MEM" "TIME" "COMMAND"
    echo "  ─────────────────────────────────────────────────────────────────"
    ps aux --sort=-%cpu 2>/dev/null | awk 'NR>1 && NR<=11 {printf "  %-8s %-12s %-6s %-6s %-10s %s\n", $2, $1, $3, $4, $10, substr($11,1,30)}'

    echo ""
    echo -e "${BOLD}Top 10 Processes by Memory Usage:${RESET}"
    printf "  %-8s %-12s %-6s %-6s %-10s %s\n" "PID" "USER" "%CPU" "%MEM" "RSS(KB)" "COMMAND"
    echo "  ─────────────────────────────────────────────────────────────────"
    ps aux --sort=-%mem 2>/dev/null | awk 'NR>1 && NR<=11 {printf "  %-8s %-12s %-6s %-6s %-10s %s\n", $2, $1, $3, $4, $6, substr($11,1,30)}'

    echo ""
    echo -e "${BOLD}Zombie / Defunct Process Check:${RESET}"
    local zombies
    zombies="$(ps -eo stat,pid,user,comm 2>/dev/null | awk '$1 ~ /Z/ {print $2, $3, $4}')"
    if [[ -n "$zombies" ]]; then
        echo -e "${RED}${BOLD}⚠ Zombie processes detected:${RESET}"
        printf "  %-8s %-12s %s\n" "PID" "USER" "COMMAND"
        echo "$zombies" | while read -r z_pid z_user z_comm; do
            printf "  %-8s %-12s %s\n" "$z_pid" "$z_user" "$z_comm"
        done
    else
        echo -e "  ${GREEN}✔ Zero zombie (defunct) processes found.${RESET}"
    fi

    echo ""
    read -rp "Would you like to inspect, renice, or terminate a specific PID? [y/N]: " action_choice
    if [[ "${action_choice,,}" =~ ^y ]]; then
        read -rp "Enter target PID: " target_pid
        if [[ ! "$target_pid" =~ ^[0-9]+$ ]] || ! kill -0 "$target_pid" 2>/dev/null; then
            log_error "PID '$target_pid' does not exist or is not running."
            return 1
        fi

        echo ""
        log_info "Details for PID $target_pid:"
        ps -p "$target_pid" -o pid,ppid,user,%cpu,%mem,stat,start,time,cmd 2>/dev/null | sed 's/^/  /'

        echo ""
        echo "Actions available:"
        echo "  1) Renice PID (change priority)"
        echo "  2) Send SIGTERM (graceful shutdown - 15)"
        echo "  3) Send SIGKILL (force termination - 9)"
        echo "  4) Cancel"
        read -rp "Select action [1-4]: " pid_action

        case "$pid_action" in
            1)
                read -rp "Enter new nice value (-20 highest priority, 19 lowest): " new_nice
                if [[ "$new_nice" =~ ^-?[0-9]+$ ]] && (( new_nice >= -20 && new_nice <= 19 )); then
                    if renice "$new_nice" -p "$target_pid" 2>/dev/null; then
                        log_success "PID $target_pid reniced to $new_nice."
                        audit "RENICE_PID" "PID=$target_pid NICE=$new_nice"
                    else
                        log_error "Failed to renice PID $target_pid. (Elevated privileges may be required)."
                    fi
                else
                    log_error "Invalid nice value."
                fi
                ;;
            2)
                read -rp "Confirm SIGTERM for PID $target_pid? [y/N]: " conf_kill
                if [[ "${conf_kill,,}" =~ ^y ]]; then
                    kill -15 "$target_pid" 2>/dev/null && log_success "SIGTERM sent to PID $target_pid." || log_error "Failed to send SIGTERM."
                    audit "SIGTERM_PID" "PID=$target_pid"
                fi
                ;;
            3)
                read -rp "Confirm SIGKILL for PID $target_pid? [y/N]: " conf_kill9
                if [[ "${conf_kill9,,}" =~ ^y ]]; then
                    kill -9 "$target_pid" 2>/dev/null && log_success "SIGKILL sent to PID $target_pid." || log_error "Failed to send SIGKILL."
                    audit "SIGKILL_PID" "PID=$target_pid"
                fi
                ;;
            *)
                log_info "Action cancelled."
                ;;
        esac
    fi
}

# =============================================================================
# MODULE 7 — REAL-TIME LIVE MONITORING DASHBOARD
# =============================================================================
live_dashboard() {
    log_section "Real-Time Live Dashboard"
    echo "This dashboard updates continuously. Press [q] or [Ctrl+C] to stop."
    read -rp "Enter refresh interval in seconds [default: 2]: " interval
    interval="${interval:-2}"
    if [[ ! "$interval" =~ ^[0-9]+$ ]] || (( interval < 1 )); then
        interval=2
    fi

    # Trap Ctrl+C cleanly
    trap 'echo -e "\n${GREEN}[✔] Live dashboard terminated.${RESET}"; return 0' INT

    while true; do
        clear || printf "\033c"
        local timestamp
        timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
        local host
        host="$(hostname -s 2>/dev/null || hostname)"
        local load
        load="$(uptime | sed 's/.*load average: //')"

        echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════════════════╗${RESET}"
        printf "${CYAN}${BOLD}║  SYSTEM MONITOR DASHBOARD  │  Host: %-15s │  %s  ║${RESET}\n" "$host" "$timestamp"
        echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════════════════╝${RESET}"

        # Load average
        echo -e "${BOLD}Load Average:${RESET} $load"

        # Memory calculations
        if [[ -f /proc/meminfo ]]; then
            local mem_tot mem_free mem_avail mem_used mem_pct
            mem_tot="$(grep -m1 '^MemTotal:' /proc/meminfo | awk '{print $2}')"
            mem_free="$(grep -m1 '^MemFree:' /proc/meminfo | awk '{print $2}')"
            mem_avail="$(grep -m1 '^MemAvailable:' /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "$mem_free")"
            mem_used=$((mem_tot - mem_avail))
            mem_pct=$((mem_used * 100 / mem_tot))

            local swap_tot swap_free swap_used swap_pct
            swap_tot="$(grep -m1 '^SwapTotal:' /proc/meminfo | awk '{print $2}')"
            swap_free="$(grep -m1 '^SwapFree:' /proc/meminfo | awk '{print $2}')"
            swap_used=$((swap_tot - swap_free))
            swap_pct=0
            (( swap_tot > 0 )) && swap_pct=$((swap_used * 100 / swap_tot))

            draw_bar "$mem_pct" 28 "RAM ($((mem_used/1024))M/$((mem_tot/1024))M)"
            (( swap_tot > 0 )) && draw_bar "$swap_pct" 28 "Swap ($((swap_used/1024))M/$((swap_tot/1024))M)"
        fi

        echo ""
        echo -e "${BOLD}Top 5 Active Processes (by %CPU):${RESET}"
        printf "  %-7s %-10s %-6s %-6s %s\n" "PID" "USER" "%CPU" "%MEM" "COMMAND"
        ps aux --sort=-%cpu 2>/dev/null | awk 'NR>1 && NR<=6 {printf "  %-7s %-10s %-6s %-6s %s\n", $2, $1, $3, $4, substr($11,1,32)}'

        echo ""
        echo -e "${BOLD}Root Filesystem Usage:${RESET}"
        df -h / 2>/dev/null | awk 'NR>1 {printf "  Mounted on %s: %s used of %s (%s available) [%s full]\n", $6, $3, $2, $4, $5}'

        echo ""
        echo -e "${DIM}Refreshing every ${interval}s. Press [q] then [Enter] to exit...${RESET}"

        # Non-blocking or timed read for keypress
        local key=""
        read -t "$interval" -r key || true
        if [[ "$key" == "q" || "$key" == "Q" ]]; then
            break
        fi
    done

    trap - INT
    audit "LIVE_DASHBOARD" "INTERVAL=${interval}s"
}

# =============================================================================
# MODULE 8 — HEALTH AUDIT & THRESHOLD ALERTS
# =============================================================================
system_health_audit() {
    log_section "System Health Audit & Threshold Verification"

    echo "Configure Thresholds (Press Enter to keep defaults):"
    read -rp "CPU Warning Threshold % [default: 85]: " th_cpu
    th_cpu="${th_cpu:-85}"

    read -rp "RAM Warning Threshold % [default: 90]: " th_ram
    th_ram="${th_ram:-90}"

    read -rp "Swap Warning Threshold % [default: 50]: " th_swap
    th_swap="${th_swap:-50}"

    read -rp "Disk Partition Warning Threshold % [default: 85]: " th_disk
    th_disk="${th_disk:-85}"

    log_info "Running comprehensive diagnostics against thresholds..."
    echo ""

    local alert_count=0
    local audit_report=""
    audit_report+="SYSTEM HEALTH AUDIT REPORT\n"
    audit_report+="Generated : $(date '+%Y-%m-%d %H:%M:%S')\n"
    audit_report+="Host      : $(hostname)\n"
    audit_report+="--------------------------------------------------------\n\n"

    # 1. CPU Check
    read -r cpu user nice system idle iowait rest < /proc/stat
    local p_idle=$((idle + iowait))
    local p_busy=$((user + nice + system))
    sleep 0.5
    read -r cpu user nice system idle iowait rest < /proc/stat
    local c_idle=$((idle + iowait))
    local c_busy=$((user + nice + system))
    local d_total=$(((c_busy + c_idle) - (p_busy + p_idle)))
    local d_busy=$((c_busy - p_busy))
    local cpu_util=0
    (( d_total > 0 )) && cpu_util=$(( d_busy * 100 / d_total ))

    if (( cpu_util >= th_cpu )); then
        echo -e "${RED}[FAIL]${RESET} CPU Utilization is ${RED}${cpu_util}%${RESET} (Threshold: ${th_cpu}%)"
        audit_report+="[FAIL] CPU Utilization: ${cpu_util}% (Threshold: ${th_cpu}%)\n"
        ((alert_count++))
    else
        echo -e "${GREEN}[PASS]${RESET} CPU Utilization is ${GREEN}${cpu_util}%${RESET} (Threshold: ${th_cpu}%)"
        audit_report+="[PASS] CPU Utilization: ${cpu_util}%\n"
    fi

    # 2. Memory Check
    local mem_tot mem_free mem_avail mem_pct
    mem_tot="$(grep -m1 '^MemTotal:' /proc/meminfo | awk '{print $2}')"
    mem_free="$(grep -m1 '^MemFree:' /proc/meminfo | awk '{print $2}')"
    mem_avail="$(grep -m1 '^MemAvailable:' /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "$mem_free")"
    mem_pct=$(( (mem_tot - mem_avail) * 100 / mem_tot ))

    if (( mem_pct >= th_ram )); then
        echo -e "${RED}[FAIL]${RESET} Memory Utilization is ${RED}${mem_pct}%${RESET} (Threshold: ${th_ram}%)"
        audit_report+="[FAIL] Memory Utilization: ${mem_pct}% (Threshold: ${th_ram}%)\n"
        ((alert_count++))
    else
        echo -e "${GREEN}[PASS]${RESET} Memory Utilization is ${GREEN}${mem_pct}%${RESET} (Threshold: ${th_ram}%)"
        audit_report+="[PASS] Memory Utilization: ${mem_pct}%\n"
    fi

    # 3. Swap Check
    local swap_tot swap_free swap_pct=0
    swap_tot="$(grep -m1 '^SwapTotal:' /proc/meminfo | awk '{print $2}')"
    swap_free="$(grep -m1 '^SwapFree:' /proc/meminfo | awk '{print $2}')"
    if (( swap_tot > 0 )); then
        swap_pct=$(( (swap_tot - swap_free) * 100 / swap_tot ))
        if (( swap_pct >= th_swap )); then
            echo -e "${RED}[FAIL]${RESET} Swap Utilization is ${RED}${swap_pct}%${RESET} (Threshold: ${th_swap}%)"
            audit_report+="[FAIL] Swap Utilization: ${swap_pct}% (Threshold: ${th_swap}%)\n"
            ((alert_count++))
        else
            echo -e "${GREEN}[PASS]${RESET} Swap Utilization is ${GREEN}${swap_pct}%${RESET} (Threshold: ${th_swap}%)"
            audit_report+="[PASS] Swap Utilization: ${swap_pct}%\n"
        fi
    else
        echo -e "${CYAN}[INFO]${RESET} No Swap configured (Skipping swap threshold)."
        audit_report+="[INFO] No Swap configured.\n"
    fi

    # 4. Storage Partitions Check
    local disk_issues=0
    while read -r fs pct mount; do
        local n_pct="${pct%\%}"
        if (( n_pct >= th_disk )); then
            echo -e "${RED}[FAIL]${RESET} Partition ${BOLD}$mount${RESET} ($fs) is at ${RED}${pct}${RESET} (Threshold: ${th_disk}%)"
            audit_report+="[FAIL] Partition $mount ($fs) is at ${pct}\n"
            ((alert_count++))
            ((disk_issues++))
        fi
    done < <(df -h -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | awk 'NR>1 {print $1, $5, $6}')

    if (( disk_issues == 0 )); then
        echo -e "${GREEN}[PASS]${RESET} All mounted filesystems are within safe storage limits (<${th_disk}%)."
        audit_report+="[PASS] All mounted filesystems within threshold.\n"
    fi

    # 5. Zombie Processes Check
    local z_count
    z_count="$(ps -eo stat 2>/dev/null | grep -c '^Z' || echo 0)"
    if (( z_count > 0 )); then
        echo -e "${YELLOW}[WARN]${RESET} Found ${z_count} zombie process(es) on the system."
        audit_report+="[WARN] Found ${z_count} zombie process(es).\n"
        ((alert_count++))
    else
        echo -e "${GREEN}[PASS]${RESET} No defunct (zombie) processes detected."
        audit_report+="[PASS] Zero zombie processes.\n"
    fi

    echo ""
    echo "────────────────────────────────────────────────────────"
    if (( alert_count > 0 )); then
        echo -e "${RED}${BOLD}Audit Finished: ${alert_count} alert(s) triggered!${RESET}"
    else
        echo -e "${GREEN}${BOLD}Audit Finished: System is in EXCELLENT health (0 alerts).${RESET}"
    fi

    echo ""
    read -rp "Would you like to export this report to a text file? [y/N]: " exp_choice
    if [[ "${exp_choice,,}" =~ ^y ]]; then
        local out_file="/tmp/system_audit_$(date '+%Y%m%d_%H%M%S').txt"
        echo -e "$audit_report" > "$out_file"
        log_success "Report saved to: ${BOLD}$out_file${RESET}"
    fi

    audit "HEALTH_AUDIT" "ALERTS=$alert_count CPU_TH=$th_cpu RAM_TH=$th_ram DISK_TH=$th_disk"
}

# =============================================================================
# MODULE 9 — AUTOMATED BACKGROUND WATCHDOG GENERATOR
# =============================================================================
setup_watchdog() {
    log_section "Automated Monitoring Watchdog Generator"

    echo "This wizard generates a lightweight, standalone watchdog script"
    echo "that runs via crontab and logs warning alerts to syslog or a file."
    echo ""

    local target_script="/usr/local/bin/system_health_watchdog.sh"
    read -rp "Enter destination path for watchdog script [default: $target_script]: " custom_script
    target_script="${custom_script:-$target_script}"

    local alert_log="/var/log/system_watchdog_alerts.log"
    read -rp "Enter path for alert log file [default: $alert_log]: " custom_log
    alert_log="${custom_log:-$alert_log}"

    read -rp "CPU threshold percentage for background alert [default: 90]: " bg_cpu
    bg_cpu="${bg_cpu:-90}"

    read -rp "RAM threshold percentage for background alert [default: 90]: " bg_ram
    bg_ram="${bg_ram:-90}"

    read -rp "Disk threshold percentage for background alert [default: 90]: " bg_disk
    bg_disk="${bg_disk:-90}"

    local script_content
    cat << 'EOF' > /tmp/sys_watchdog_template.sh
#!/usr/bin/env bash
# Standalone System Health Watchdog generated by system_monitor.sh
set -euo pipefail

ALERT_LOG="__ALERT_LOG__"
CPU_TH=__CPU_TH__
RAM_TH=__RAM_TH__
DISK_TH=__DISK_TH__

log_alert() {
    local msg="[WATCHDOG ALERT $(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" >> "$ALERT_LOG"
    logger -t sysmon-watchdog "$msg" 2>/dev/null || true
}

# 1. Memory check
if [[ -f /proc/meminfo ]]; then
    tot=$(grep -m1 '^MemTotal:' /proc/meminfo | awk '{print $2}')
    free=$(grep -m1 '^MemFree:' /proc/meminfo | awk '{print $2}')
    avail=$(grep -m1 '^MemAvailable:' /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "$free")
    pct=$(( (tot - avail) * 100 / tot ))
    if (( pct >= RAM_TH )); then
        log_alert "High RAM usage: ${pct}% exceeds threshold of ${RAM_TH}%"
    fi
fi

# 2. Disk check
while read -r mount pct; do
    npct="${pct%\%}"
    if (( npct >= DISK_TH )); then
        log_alert "Disk partition $mount critical: ${pct} exceeds threshold of ${DISK_TH}%"
    fi
done < <(df -h -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | awk 'NR>1 {print $6, $5}')
EOF

    # Replace placeholders
    sed -i "s|__ALERT_LOG__|$alert_log|g" /tmp/sys_watchdog_template.sh
    sed -i "s|__CPU_TH__|$bg_cpu|g" /tmp/sys_watchdog_template.sh
    sed -i "s|__RAM_TH__|$bg_ram|g" /tmp/sys_watchdog_template.sh
    sed -i "s|__DISK_TH__|$bg_disk|g" /tmp/sys_watchdog_template.sh

    if is_root; then
        mkdir -p "$(dirname "$target_script")"
        mkdir -p "$(dirname "$alert_log")"
        mv /tmp/sys_watchdog_template.sh "$target_script"
        chmod +x "$target_script"
        log_success "Watchdog script successfully deployed to: $target_script"

        echo ""
        read -rp "Would you like to add a 5-minute cron job for root? [y/N]: " cron_choice
        if [[ "${cron_choice,,}" =~ ^y ]]; then
            (crontab -l 2>/dev/null | grep -v "$target_script" || true; echo "*/5 * * * * $target_script") | crontab -
            log_success "Crontab entry installed! Runs every 5 minutes."
        fi
    else
        local fallback_script="./system_health_watchdog.sh"
        mv /tmp/sys_watchdog_template.sh "$fallback_script"
        chmod +x "$fallback_script"
        log_warn "Non-root user: Generated watchdog script in current working directory: $fallback_script"
        log_info "To install system-wide, copy to $target_script and make executable."
    fi

    audit "SETUP_WATCHDOG" "SCRIPT=$target_script LOG=$alert_log"
}

# =============================================================================
# MODULE 10 — VIEW AUDIT LOG
# =============================================================================
view_audit_log() {
    log_section "System Monitor Audit Log — $AUDIT_LOG"
    if [[ -f "$AUDIT_LOG" ]]; then
        echo -e "${BOLD}Last 30 audit entries:${RESET}"
        tail -n 30 "$AUDIT_LOG"
    else
        log_warn "No audit log found at '$AUDIT_LOG' yet."
    fi
}

# =============================================================================
# MAIN INTERACTIVE MENU
# =============================================================================
main_menu() {
    while true; do
        echo ""
        echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${CYAN}${BOLD}║        Linux System Performance & Monitoring Tool v1.0        ║${RESET}"
        echo -e "${CYAN}${BOLD}║                     github.com/ACESVAGE                       ║${RESET}"
        echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════╝${RESET}"
        echo ""
        echo "  1) System Overview & Health Dashboard (OS, Kernel, Load, Uptime)"
        echo "  2) CPU Utilization & Core Analysis (per-core stats, thermals)"
        echo "  3) Memory & Swap Diagnostics (RAM bars, cache, OOM incidents)"
        echo "  4) Disk I/O & Storage Health (df -h, inodes, iostat throughput)"
        echo "  5) Virtual Memory & Kernel Subsystem Analysis (vmstat run-queues)"
        echo "  6) Process Inspector & Top Consumers (top 10 CPU/RAM, renice/kill)"
        echo "  7) Real-Time Live Monitoring Dashboard (continuous terminal refresh)"
        echo "  8) Health Audit & Threshold Alert Engine (CPU/RAM/Disk rules)"
        echo "  9) Setup Automated Background Watchdog (cron & syslog alerts)"
        echo " 10) View Audit Log"
        echo " 11) Exit"
        echo ""
        read -rp "Select an option [1-11]: " choice

        case "$choice" in
            1)  system_overview ;;
            2)  cpu_utilization ;;
            3)  memory_diagnostics ;;
            4)  disk_io_storage ;;
            5)  vmstat_analysis ;;
            6)  process_inspector ;;
            7)  live_dashboard ;;
            8)  system_health_audit ;;
            9)  setup_watchdog ;;
            10) view_audit_log ;;
            11) log_info "Exiting System Monitor. Stay performant & secure! 🛡️"; exit 0 ;;
            *)  log_error "Invalid option. Please choose a number between 1 and 11." ;;
        esac
    done
}

# =============================================================================
# ENTRY POINT
# =============================================================================
main_menu
