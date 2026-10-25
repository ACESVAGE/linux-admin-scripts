#!/usr/bin/env bash
# =============================================================================
# disk_management.sh â€” Linux Disk & Storage Administration Tool
# =============================================================================
# Author      : ACESVAGE
# Repository  : https://github.com/ACESVAGE/linux-admin-scripts
# Description : Interactive menu-driven script for managing Linux disk storage.
#               Covers disk usage, cleanup, partitioning info, mounts,
#               filesystem checks, and large-file hunting.
#
# Usage       : sudo ./disk_management.sh
# Requirements: Must be run as root (or via sudo) for full functionality
# Tested on   : Ubuntu 20.04+, Debian 11+, CentOS/RHEL 8+
# =============================================================================

set -euo pipefail

# â”€â”€ Colours â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# â”€â”€ Logging helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
log_info()    { echo -e "${GREEN}[INFO]${RESET}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_success() { echo -e "${GREEN}[âœ”]${RESET} $*"; }
log_section() { echo -e "\n${CYAN}${BOLD}â•â• $* â•â•${RESET}"; }

# â”€â”€ Root check â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root. Use: sudo $0"
        exit 1
    fi
}

# â”€â”€ Dependency check â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
require_cmd() {
    command -v "$1" &>/dev/null || { log_warn "'$1' not found â€” some features may be limited."; return 1; }
}

# â”€â”€ Audit log â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
AUDIT_LOG="/var/log/disk_management_audit.log"

audit() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | USER=$(logname 2>/dev/null || echo root) | ACTION=$1 | DETAIL=$2" \
        >> "$AUDIT_LOG" 2>/dev/null || true
}

# =============================================================================
# SECTION 1 â€” DISK USAGE OVERVIEW
# =============================================================================
disk_usage_overview() {
    log_section "Disk Usage Overview"

    echo ""
    echo -e "${BOLD}â”€â”€ Filesystem Usage (df -hT) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€${RESET}"
    df -hT | grep -v "tmpfs\|devtmpfs\|udev\|none" | \
        awk 'NR==1{print} NR>1{
            pct=$6+0
            if(pct>=90) color="\033[0;31m"
            else if(pct>=75) color="\033[1;33m"
            else color="\033[0;32m"
            printf "%s%s\033[0m\n", color, $0
        }'

    echo ""
    echo -e "${BOLD}â”€â”€ Inode Usage (df -i) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€${RESET}"
    df -i | grep -v "tmpfs\|devtmpfs\|udev\|none" | \
        awk 'NR==1{print} NR>1{
            pct=$5+0
            if(pct>=90) color="\033[0;31m"
            else if(pct>=75) color="\033[1;33m"
            else color="\033[0;32m"
            printf "%s%s\033[0m\n", color, $0
        }'

    echo ""
    echo -e "${BOLD}â”€â”€ Block Devices (lsblk) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€${RESET}"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL 2>/dev/null || lsblk

    audit "DISK_USAGE_OVERVIEW" "ran"
}

# =============================================================================
# SECTION 2 â€” DIRECTORY SIZE ANALYSIS
# =============================================================================
directory_size_analysis() {
    log_section "Directory Size Analysis"

    echo "  1) Show top 10 largest directories from /"
    echo "  2) Show top 10 largest directories from a custom path"
    echo "  3) Show sizes of immediate subdirectories"
    echo ""
    read -rp "Choose option [1-3]: " dir_choice

    case "$dir_choice" in
        1)
            log_info "Scanning / for top 10 largest directories (this may take a moment)..."
            du -ahx / 2>/dev/null | sort -rh | head -20
            ;;
        2)
            read -rp "Enter path to scan: " scan_path
            if [[ ! -d "$scan_path" ]]; then
                log_error "Directory '$scan_path' does not exist."; return 1
            fi
            log_info "Scanning '$scan_path'..."
            du -ahx "$scan_path" 2>/dev/null | sort -rh | head -20
            ;;
        3)
            read -rp "Enter path [default: /]: " scan_path
            scan_path="${scan_path:-/}"
            if [[ ! -d "$scan_path" ]]; then
                log_error "Directory '$scan_path' does not exist."; return 1
            fi
            log_info "Immediate subdirectory sizes for '$scan_path':"
            du -hx --max-depth=1 "$scan_path" 2>/dev/null | sort -rh
            ;;
        *)
            log_error "Invalid option."
            ;;
    esac

    audit "DIR_SIZE_ANALYSIS" "${scan_path:-/}"
}

# =============================================================================
# SECTION 3 â€” LARGE FILE HUNTER
# =============================================================================
large_file_hunter() {
    log_section "Large File Hunter"

    read -rp "Search from path [default: /]: " search_path
    search_path="${search_path:-/}"

    read -rp "Minimum file size [default: 100M] (e.g. 50M, 1G): " min_size
    min_size="${min_size:-100M}"

    read -rp "How many results to show? [default: 20]: " result_count
    result_count="${result_count:-20}"

    log_info "Hunting for files larger than $min_size in '$search_path'..."
    echo ""

    find "$search_path" -xdev -type f -size "+${min_size}" 2>/dev/null \
        -exec ls -lh {} \; | \
        awk '{print $5, $9}' | sort -rh | head -"$result_count" | \
        awk '{printf "%-10s %s\n", $1, $2}'

    audit "LARGE_FILE_HUNT" "path=$search_path size>$min_size"
}

# =============================================================================
# SECTION 4 â€” DISK CLEANUP
# =============================================================================
disk_cleanup() {
    log_section "Disk Cleanup"

    echo "  1) Clean package manager cache (apt/yum/dnf)"
    echo "  2) Remove old log files (> N days)"
    echo "  3) Clear systemd journal logs"
    echo "  4) Remove orphaned packages"
    echo "  5) Find and remove duplicate files (by size+name)"
    echo "  6) Truncate a specific log file safely"
    echo "  7) Clean /tmp directory"
    echo ""
    read -rp "Choose option [1-7]: " clean_choice

    case "$clean_choice" in
        1)
            if command -v apt-get &>/dev/null; then
                log_info "Running apt-get autoremove + autoclean..."
                apt-get autoremove -y
                apt-get autoclean -y
                apt-get clean
                log_success "APT cache cleaned."
            elif command -v dnf &>/dev/null; then
                log_info "Running dnf clean all..."
                dnf clean all
                log_success "DNF cache cleaned."
            elif command -v yum &>/dev/null; then
                log_info "Running yum clean all..."
                yum clean all
                log_success "YUM cache cleaned."
            else
                log_warn "No supported package manager found (apt/yum/dnf)."
            fi
            audit "CLEAN_PKG_CACHE" "done"
            ;;
        2)
            read -rp "Remove logs older than how many days? [default: 30]: " log_days
            log_days="${log_days:-30}"
            read -rp "Log directory [default: /var/log]: " log_dir
            log_dir="${log_dir:-/var/log}"
            log_warn "The following log files would be deleted (older than $log_days days):"
            find "$log_dir" -type f -name "*.log" -mtime +"$log_days" 2>/dev/null
            read -rp "Proceed with deletion? [y/N]: " confirm_del
            if [[ "${confirm_del,,}" == "y" ]]; then
                find "$log_dir" -type f -name "*.log" -mtime +"$log_days" -delete 2>/dev/null
                log_success "Old log files deleted."
                audit "CLEAN_OLD_LOGS" "dir=$log_dir days=$log_days"
            else
                log_info "Aborted."
            fi
            ;;
        3)
            log_info "Current journal disk usage:"
            journalctl --disk-usage 2>/dev/null || log_warn "journalctl not available."
            read -rp "Retain only last N days of journal [default: 7]: " journal_days
            journal_days="${journal_days:-7}"
            journalctl --vacuum-time="${journal_days}d"
            log_success "Journal vacuumed to last $journal_days days."
            audit "CLEAN_JOURNAL" "retained=${journal_days}d"
            ;;
        4)
            if command -v apt-get &>/dev/null; then
                log_info "Removing orphaned packages..."
                apt-get autoremove -y
                log_success "Orphaned packages removed."
            elif command -v dnf &>/dev/null; then
                dnf autoremove -y
                log_success "Orphaned packages removed."
            else
                log_warn "Manual check required for your distro."
            fi
            audit "CLEAN_ORPHANS" "done"
            ;;
        5)
            read -rp "Search path for duplicates [default: /home]: " dup_path
            dup_path="${dup_path:-/home}"
            log_info "Finding potential duplicates by name+size in '$dup_path'..."
            find "$dup_path" -type f -printf '%s %f\n' 2>/dev/null | \
                sort | uniq -d | head -30
            log_warn "Review the above before manual deletion."
            audit "FIND_DUPLICATES" "path=$dup_path"
            ;;
        6)
            read -rp "Enter full path of log file to truncate: " trunc_file
            if [[ ! -f "$trunc_file" ]]; then
                log_error "File '$trunc_file' not found."; return 1
            fi
            local size_before
            size_before=$(du -sh "$trunc_file" | cut -f1)
            log_warn "This will truncate (empty) '$trunc_file' (current size: $size_before)."
            read -rp "Confirm? [y/N]: " trunc_confirm
            if [[ "${trunc_confirm,,}" == "y" ]]; then
                > "$trunc_file"
                log_success "'$trunc_file' truncated (was $size_before)."
                audit "TRUNCATE_LOG" "$trunc_file (was $size_before)"
            else
                log_info "Aborted."
            fi
            ;;
        7)
            log_info "Current /tmp usage: $(du -sh /tmp 2>/dev/null | cut -f1)"
            log_warn "Files in /tmp older than 1 day will be removed."
            read -rp "Proceed? [y/N]: " tmp_confirm
            if [[ "${tmp_confirm,,}" == "y" ]]; then
                find /tmp -type f -mtime +1 -delete 2>/dev/null
                find /tmp -type d -empty -mtime +1 -delete 2>/dev/null
                log_success "/tmp cleaned."
                audit "CLEAN_TMP" "done"
            else
                log_info "Aborted."
            fi
            ;;
        *)
            log_error "Invalid option."
            ;;
    esac
}

# =============================================================================
# SECTION 5 â€” MOUNT MANAGEMENT
# =============================================================================
mount_management() {
    log_section "Mount Management"

    echo "  1) Show all current mounts"
    echo "  2) Mount a device"
    echo "  3) Unmount a device"
    echo "  4) Show /etc/fstab"
    echo "  5) Check if a path is a mount point"
    echo ""
    read -rp "Choose option [1-5]: " mnt_choice

    case "$mnt_choice" in
        1)
            log_section "Current Mounts"
            mount | column -t | grep -v "cgroup\|proc\|sysfs\|devpts\|tmpfs\|securityfs\|pstore\|bpf\|tracefs\|debugfs\|mqueue\|hugetlbfs\|fusectl" | sort
            ;;
        2)
            read -rp "Device to mount (e.g. /dev/sdb1): " mnt_device
            read -rp "Mount point (e.g. /mnt/data): " mnt_point
            read -rp "Filesystem type [default: auto]: " mnt_type
            mnt_type="${mnt_type:-auto}"
            read -rp "Mount options [default: defaults]: " mnt_opts
            mnt_opts="${mnt_opts:-defaults}"

            mkdir -p "$mnt_point"
            mount -t "$mnt_type" -o "$mnt_opts" "$mnt_device" "$mnt_point"
            log_success "Mounted '$mnt_device' at '$mnt_point'."
            audit "MOUNT" "$mnt_device -> $mnt_point"

            read -rp "Add to /etc/fstab for persistence? [y/N]: " fstab_add
            if [[ "${fstab_add,,}" == "y" ]]; then
                local uuid
                uuid=$(blkid -s UUID -o value "$mnt_device" 2>/dev/null || echo "$mnt_device")
                echo "UUID=$uuid  $mnt_point  $mnt_type  $mnt_opts  0  2" >> /etc/fstab
                log_success "Entry added to /etc/fstab."
                audit "FSTAB_ADD" "$mnt_device UUID=$uuid"
            fi
            ;;
        3)
            read -rp "Enter device or mount point to unmount: " umnt_target
            umount "$umnt_target"
            log_success "Unmounted '$umnt_target'."
            audit "UMOUNT" "$umnt_target"
            ;;
        4)
            log_section "/etc/fstab"
            cat -n /etc/fstab
            ;;
        5)
            read -rp "Enter path to check: " check_path
            if mountpoint -q "$check_path"; then
                log_success "'$check_path' IS a mount point."
            else
                log_warn "'$check_path' is NOT a mount point."
            fi
            ;;
        *)
            log_error "Invalid option."
            ;;
    esac
}

# =============================================================================
# SECTION 6 â€” PARTITION & BLOCK DEVICE INFO
# =============================================================================
partition_info() {
    log_section "Partition & Block Device Info"

    echo "  1) List all block devices (lsblk)"
    echo "  2) Show partition table (fdisk -l)"
    echo "  3) Show disk UUIDs and labels (blkid)"
    echo "  4) Show SMART disk health (smartctl)"
    echo "  5) Show disk I/O stats (iostat)"
    echo ""
    read -rp "Choose option [1-5]: " part_choice

    case "$part_choice" in
        1)
            lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL,UUID
            ;;
        2)
            fdisk -l 2>/dev/null || log_warn "fdisk not available or no disks found."
            ;;
        3)
            blkid
            ;;
        4)
            if require_cmd smartctl; then
                read -rp "Enter disk device (e.g. /dev/sda): " smart_dev
                smartctl -H "$smart_dev"
                echo ""
                log_info "Full SMART info:"
                smartctl -a "$smart_dev" | grep -E "Device Model|Serial|Reallocated|Power_On|Temp|Pending|Uncorrectable|SMART overall"
            fi
            ;;
        5)
            if require_cmd iostat; then
                log_info "Disk I/O statistics (1 sample):"
                iostat -xh 1 1
            fi
            ;;
        *)
            log_error "Invalid option."
            ;;
    esac

    audit "PARTITION_INFO" "option=$part_choice"
}

# =============================================================================
# SECTION 7 â€” FILESYSTEM HEALTH CHECK
# =============================================================================
filesystem_check() {
    log_section "Filesystem Health Check"

    echo "  1) Check filesystem on an unmounted partition (fsck)"
    echo "  2) Show filesystem type and details (tune2fs / xfs_info)"
    echo "  3) Check for filesystem errors in system logs"
    echo ""
    read -rp "Choose option [1-3]: " fs_choice

    case "$fs_choice" in
        1)
            read -rp "Enter device to check (e.g. /dev/sdb1): " fs_device
            log_warn "Ensure '$fs_device' is UNMOUNTED before running fsck."
            read -rp "Proceed? [y/N]: " fs_confirm
            if [[ "${fs_confirm,,}" == "y" ]]; then
                fsck -n "$fs_device" && log_success "Filesystem check passed." || log_error "Issues found. Run 'fsck $fs_device' manually."
                audit "FSCK" "$fs_device"
            fi
            ;;
        2)
            read -rp "Enter device (e.g. /dev/sda1): " fs_dev2
            local fstype
            fstype=$(blkid -o value -s TYPE "$fs_dev2" 2>/dev/null || echo "unknown")
            log_info "Filesystem type: $fstype"
            case "$fstype" in
                ext2|ext3|ext4)
                    tune2fs -l "$fs_dev2" 2>/dev/null | grep -E "Filesystem|Block|Inode|Mount|Last|Errors"
                    ;;
                xfs)
                    xfs_info "$fs_dev2" 2>/dev/null || log_warn "xfs_info not available."
                    ;;
                *)
                    log_warn "Detailed info not available for '$fstype'. Use blkid or lsblk."
                    ;;
            esac
            ;;
        3)
            log_section "Filesystem Errors in System Logs"
            dmesg | grep -iE "error|fail|corrupt|bad sector|I/O error|ext4|xfs|btrfs" | tail -30 || true
            echo ""
            grep -iE "error|fail|i/o|corrupt" /var/log/syslog 2>/dev/null | tail -20 || \
            grep -iE "error|fail|i/o|corrupt" /var/log/messages 2>/dev/null | tail -20 || \
            log_warn "No syslog/messages file found."
            ;;
        *)
            log_error "Invalid option."
            ;;
    esac
}

# =============================================================================
# SECTION 8 â€” SWAP MANAGEMENT
# =============================================================================
swap_management() {
    log_section "Swap Management"

    echo ""
    echo -e "${BOLD}Current Swap Usage:${RESET}"
    swapon --show 2>/dev/null || echo "  No swap active."
    echo ""
    free -h
    echo ""

    echo "  1) Enable a swap partition"
    echo "  2) Create and enable a swap file"
    echo "  3) Disable swap"
    echo "  4) Clear swap (swapoff + swapon)"
    echo ""
    read -rp "Choose option [1-4]: " swap_choice

    case "$swap_choice" in
        1)
            read -rp "Enter partition (e.g. /dev/sdb2): " swap_dev
            mkswap "$swap_dev"
            swapon "$swap_dev"
            log_success "Swap enabled on '$swap_dev'."
            audit "SWAP_ENABLE" "$swap_dev"
            ;;
        2)
            read -rp "Swap file size (e.g. 2G, 512M): " swap_size
            read -rp "Swap file path [default: /swapfile]: " swap_file
            swap_file="${swap_file:-/swapfile}"

            log_info "Creating $swap_size swap file at '$swap_file'..."
            fallocate -l "$swap_size" "$swap_file" 2>/dev/null || dd if=/dev/zero of="$swap_file" bs=1M count="$(echo "$swap_size" | sed 's/G/*1024/;s/M//' | bc)" status=progress
            chmod 600 "$swap_file"
            mkswap "$swap_file"
            swapon "$swap_file"
            log_success "Swap file '$swap_file' ($swap_size) activated."

            read -rp "Add to /etc/fstab for persistence? [y/N]: " fstab_swap
            if [[ "${fstab_swap,,}" == "y" ]]; then
                echo "$swap_file  none  swap  sw  0  0" >> /etc/fstab
                log_success "Added to /etc/fstab."
            fi
            audit "SWAP_FILE_CREATE" "$swap_file size=$swap_size"
            ;;
        3)
            swapoff -a
            log_success "All swap disabled."
            audit "SWAP_DISABLE" "all"
            ;;
        4)
            log_info "Clearing swap (this may take a moment)..."
            swapoff -a && swapon -a
            log_success "Swap cleared and re-enabled."
            audit "SWAP_CLEAR" "done"
            ;;
        *)
            log_error "Invalid option."
            ;;
    esac
}

# =============================================================================
# MAIN MENU
# =============================================================================
main_menu() {
    while true; do
        echo ""
        echo -e "${CYAN}${BOLD}â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—${RESET}"
        echo -e "${CYAN}${BOLD}â•‘      Linux Disk Management Tool v1.0         â•‘${RESET}"
        echo -e "${CYAN}${BOLD}â•‘         github.com/ACESVAGE                  â•‘${RESET}"
        echo -e "${CYAN}${BOLD}â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${RESET}"
        echo ""
        echo "  1) Disk usage overview"
        echo "  2) Directory size analysis"
        echo "  3) Large file hunter"
        echo "  4) Disk cleanup"
        echo "  5) Mount management"
        echo "  6) Partition & block device info"
        echo "  7) Filesystem health check"
        echo "  8) Swap management"
        echo "  9) View audit log"
        echo " 10) Exit"
        echo ""
        read -rp "Select an option [1-10]: " choice

        case "$choice" in
            1)  disk_usage_overview ;;
            2)  directory_size_analysis ;;
            3)  large_file_hunter ;;
            4)  disk_cleanup ;;
            5)  mount_management ;;
            6)  partition_info ;;
            7)  filesystem_check ;;
            8)  swap_management ;;
            9)
                log_section "Audit Log â€” $AUDIT_LOG"
                if [[ -f "$AUDIT_LOG" ]]; then
                    tail -50 "$AUDIT_LOG"
                else
                    log_warn "No audit log found yet."
                fi
                ;;
           10)  log_info "Exiting. Stay sharp! ðŸ›¡ï¸"; exit 0 ;;
            *)  log_error "Invalid option. Choose 1â€“10." ;;
        esac
    done
}

# =============================================================================
# ENTRY POINT
# =============================================================================
check_root
main_menu
