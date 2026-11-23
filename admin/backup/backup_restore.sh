#!/usr/bin/env bash
# =============================================================================
# backup_restore.sh — Linux Backup & Restore Administration Tool
# =============================================================================
# Author      : ACESVAGE
# Repository  : https://github.com/ACESVAGE/linux-admin-scripts
# Description : Comprehensive, interactive menu-driven tool for managing Linux
#               system & data backups and restorations. Supports tar archives
#               (gzip, bzip2, xz), listed incremental backups, rsync mirrors,
#               checksum verification, rotation/retention policies, critical
#               system config snapshots, and cron job scheduling.
#
# Usage       : sudo ./backup_restore.sh
# Requirements: bash 4+, coreutils, tar, rsync, gzip, bzip2, xz, sha256sum
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
RESET='\033[0m'

# ── Logging Helpers ──────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${RESET}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET}   $*" >&2; }
log_success() { echo -e "${GREEN}[✔]${RESET}       $*"; }
log_section() { echo -e "\n${CYAN}${BOLD}══ $* ══${RESET}"; }

# ── Root Check ───────────────────────────────────────────────────────────────
check_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        log_error "This script requires root privileges to preserve file ownership and permissions."
        echo -e "Please run with: ${BOLD}sudo $0${RESET}\n"
        exit 1
    fi
}

# ── Audit Logging ────────────────────────────────────────────────────────────
AUDIT_LOG="/var/log/backup_restore_audit.log"

audit() {
    local action="$1"
    local details="$2"
    local run_user
    run_user="${SUDO_USER:-$(logname 2>/dev/null || echo "root")}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    echo "$timestamp | USER=$run_user | ACTION=$action | $details" >> "$AUDIT_LOG" 2>/dev/null || true
}

# ── Helper: Check Dependency ─────────────────────────────────────────────────
require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required tool '$cmd' is not installed."
        read -rp "Attempt to install '$cmd'? [y/N]: " inst_choice
        if [[ "${inst_choice,,}" =~ ^y ]]; then
            if command -v apt-get &>/dev/null; then
                apt-get update -y && apt-get install -y "$cmd"
            elif command -v dnf &>/dev/null; then
                dnf install -y "$cmd"
            elif command -v pacman &>/dev/null; then
                pacman -S --noconfirm "$cmd"
            elif command -v yum &>/dev/null; then
                yum install -y "$cmd"
            else
                log_error "Package manager not recognized. Please install '$cmd' manually."
                return 1
            fi
        else
            return 1
        fi
    fi
}

# =============================================================================
# MODULE 1 — FULL ARCHIVE (TAR + COMPRESSION)
# =============================================================================
create_full_archive() {
    log_section "Create Full Archive (Tar)"

    read -rp "Enter source path to backup (file or folder): " src_path
    if [[ -z "$src_path" || ! -e "$src_path" ]]; then
        log_error "Source path '$src_path' does not exist."
        return 1
    fi
    src_path="$(realpath "$src_path")"

    read -rp "Enter destination directory [default: /var/backups]: " dest_dir
    dest_dir="${dest_dir:-/var/backups}"
    mkdir -p "$dest_dir"

    echo ""
    echo "Choose compression algorithm:"
    echo "  1) gzip  (.tar.gz)   - Fast, good compression (Default)"
    echo "  2) bzip2 (.tar.bz2)  - Higher compression, slower"
    echo "  3) xz    (.tar.xz)   - Maximum compression ratio, CPU-heavy"
    echo "  4) none  (.tar)      - Uncompressed archive"
    read -rp "Select compression [1-4, default 1]: " comp_opt
    comp_opt="${comp_opt:-1}"

    local ext="tar.gz"
    local tar_flag="-czf"
    case "$comp_opt" in
        1) ext="tar.gz";  tar_flag="-czf"; require_cmd gzip  || return 1 ;;
        2) ext="tar.bz2"; tar_flag="-cjf"; require_cmd bzip2 || return 1 ;;
        3) ext="tar.xz";  tar_flag="-cJf"; require_cmd xz    || return 1 ;;
        4) ext="tar";     tar_flag="-cf" ;;
        *) log_warn "Invalid selection. Defaulting to gzip."; ext="tar.gz"; tar_flag="-czf" ;;
    esac

    local base_name
    base_name="$(basename "$src_path")"
    local timestamp
    timestamp="$(date +'%Y%m%d_%H%M%S')"
    local archive_name="${base_name}_full_${timestamp}.${ext}"
    local archive_path="${dest_dir}/${archive_name}"

    read -rp "Exclude patterns? (space-separated, e.g., *.tmp .git node_modules) [optional]: " excludes

    local exclude_args=()
    if [[ -n "$excludes" ]]; then
        for ex in $excludes; do
            exclude_args+=("--exclude=$ex")
        done
    fi

    log_info "Source      : $src_path"
    log_info "Destination : $archive_path"
    log_info "Archiving with permissions & ownership preservation..."

    local parent_dir
    parent_dir="$(dirname "$src_path")"
    local target_item
    target_item="$(basename "$src_path")"

    if tar "${exclude_args[@]}" -p --numeric-owner "$tar_flag" "$archive_path" -C "$parent_dir" "$target_item"; then
        local arc_size
        arc_size="$(du -h "$archive_path" | awk '{print $1}')"
        log_success "Archive created successfully! (Size: $arc_size)"

        # Generate sha256 checksum
        log_info "Calculating SHA-256 integrity checksum..."
        local chksum
        chksum="$(sha256sum "$archive_path" | awk '{print $1}')"
        echo "$chksum  $archive_name" > "${archive_path}.sha256"
        log_success "Checksum written: ${archive_path}.sha256"
        echo -e "  SHA256: ${MAGENTA}$chksum${RESET}"

        audit "FULL_BACKUP" "SOURCE=$src_path ARCHIVE=$archive_path SIZE=$arc_size SHA256=$chksum"
    else
        log_error "Archive creation failed."
        return 1
    fi
}

# =============================================================================
# MODULE 2 — INCREMENTAL BACKUP (TAR LISTED-INCREMENTAL)
# =============================================================================
create_incremental_backup() {
    log_section "Create Listed Incremental Backup (Tar Snapshot)"
    echo "Incremental backups only save files modified since the previous backup level."

    read -rp "Enter source directory to backup: " src_dir
    if [[ -z "$src_dir" || ! -d "$src_dir" ]]; then
        log_error "Source directory '$src_dir' does not exist."
        return 1
    fi
    src_dir="$(realpath "$src_dir")"

    read -rp "Enter destination backup directory [default: /var/backups]: " dest_dir
    dest_dir="${dest_dir:-/var/backups}"
    mkdir -p "$dest_dir"

    local base_name
    base_name="$(basename "$src_dir")"
    local snapshot_file="${dest_dir}/${base_name}.snar"

    local is_full="Incremental"
    if [[ ! -f "$snapshot_file" ]]; then
        is_full="Base Full (Level 0)"
        log_info "No snapshot file found at '$snapshot_file'. Initializing $is_full."
    else
        log_info "Existing snapshot found. Appending incremental changes."
    fi

    local timestamp
    timestamp="$(date +'%Y%m%d_%H%M%S')"
    local archive_name="${base_name}_incr_${timestamp}.tar.gz"
    local archive_path="${dest_dir}/${archive_name}"

    local parent_dir
    parent_dir="$(dirname "$src_dir")"
    local target_item
    target_item="$(basename "$src_dir")"

    log_info "Building $is_full archive -> $archive_path"

    if tar -p --numeric-owner --listed-incremental="$snapshot_file" -czf "$archive_path" -C "$parent_dir" "$target_item"; then
        local arc_size
        arc_size="$(du -h "$archive_path" | awk '{print $1}')"
        log_success "Incremental backup created! (Type: $is_full, Size: $arc_size)"

        sha256sum "$archive_path" > "${archive_path}.sha256"
        audit "INCR_BACKUP" "SOURCE=$src_dir ARCHIVE=$archive_path TYPE=$is_full SIZE=$arc_size"
    else
        log_error "Incremental backup failed."
        return 1
    fi
}

# =============================================================================
# MODULE 3 — RSYNC DIRECTORY SYNC / MIRROR
# =============================================================================
rsync_mirror() {
    log_section "Directory Synchronization (rsync)"
    require_cmd rsync || return 1

    read -rp "Enter source directory (e.g. /home/user/data or /var/www): " src_path
    if [[ -z "$src_path" ]]; then
        log_error "Source path cannot be empty."
        return 1
    fi

    read -rp "Enter destination (local path or remote user@host:/path): " dest_path
    if [[ -z "$dest_path" ]]; then
        log_error "Destination path cannot be empty."
        return 1
    fi

    # Trailing slash convention explanation
    echo -e "\n${YELLOW}Note on trailing slash:${RESET}"
    echo "  - '/data'  -> Creates destination folder named 'data' (e.g., /dest/data)"
    echo "  - '/data/' -> Syncs the *contents* directly into the destination"
    read -rp "Ensure trailing slash on source to sync contents? [Y/n]: " add_slash
    add_slash="${add_slash:-Y}"
    if [[ "${add_slash,,}" =~ ^y && "${src_path: -1}" != "/" ]]; then
        src_path="${src_path}/"
    fi

    echo ""
    read -rp "Delete files from destination that no longer exist in source (--delete)? [y/N]: " del_opt
    del_opt="${del_opt:-N}"

    read -rp "Perform Dry Run first (preview without writing changes)? [Y/n]: " dry_opt
    dry_opt="${dry_opt:-Y}"

    local rsync_flags=("-avhP")
    if [[ "${del_opt,,}" =~ ^y ]]; then
        rsync_flags+=("--delete")
    fi

    if [[ "${dry_opt,,}" =~ ^y ]]; then
        log_info "Executing DRY RUN (Simulation)..."
        echo -e "${MAGENTA}rsync ${rsync_flags[*]} --dry-run \"$src_path\" \"$dest_path\"${RESET}\n"
        rsync "${rsync_flags[@]}" --dry-run "$src_path" "$dest_path"
        echo ""
        read -rp "Dry run completed. Proceed with ACTUAL synchronization? [y/N]: " proceed
        if [[ ! "${proceed,,}" =~ ^y ]]; then
            log_info "Sync aborted by user."
            return 0
        fi
    fi

    log_info "Starting real synchronization..."
    if rsync "${rsync_flags[@]}" "$src_path" "$dest_path"; then
        log_success "Rsync synchronization finished successfully."
        audit "RSYNC_SYNC" "SRC=$src_path DEST=$dest_path DELETE=${del_opt^^}"
    else
        log_error "Rsync synchronization returned an error."
        return 1
    fi
}

# =============================================================================
# MODULE 4 — VERIFY ARCHIVE INTEGRITY & INSPECT CONTENTS
# =============================================================================
verify_and_inspect_archive() {
    log_section "Verify Archive Integrity & Inspect Contents"

    read -rp "Enter path to archive file (tar, tar.gz, tar.bz2, tar.xz): " arc_file
    if [[ -z "$arc_file" || ! -f "$arc_file" ]]; then
        log_error "Archive file '$arc_file' does not exist."
        return 1
    fi

    echo ""
    log_info "Archive File: $arc_file"
    log_info "Size: $(du -h "$arc_file" | awk '{print $1}')"
    log_info "Last Modified: $(date -r "$arc_file" '+%Y-%m-%d %H:%M:%S')"

    # Check SHA256 if .sha256 file exists alongside
    if [[ -f "${arc_file}.sha256" ]]; then
        log_info "Found companion checksum file (${arc_file}.sha256). Verifying..."
        if (cd "$(dirname "$arc_file")" && sha256sum -c "$(basename "${arc_file}.sha256")"); then
            log_success "SHA-256 checksum matches! File is untampered and consistent."
        else
            log_error "Checksum verification FAILED! The archive may be corrupted or modified."
        fi
    else
        log_warn "No .sha256 companion file found. Calculating current SHA-256:"
        sha256sum "$arc_file"
    fi

    echo ""
    log_info "Testing archive integrity through tar..."
    if tar -tf "$arc_file" >/dev/null 2>&1; then
        log_success "Tar archive integrity check PASSED! Archive headers and data blocks are valid."
    else
        log_error "Tar archive integrity test FAILED. Archive is corrupted or unreadable."
        return 1
    fi

    echo ""
    read -rp "List files contained inside the archive? [y/N]: " list_opt
    if [[ "${list_opt,,}" =~ ^y ]]; then
        echo -e "\n${BOLD}Files inside archive (first 50 shown):${RESET}"
        tar -tf "$arc_file" | head -n 50
        local total_files
        total_files="$(tar -tf "$arc_file" | wc -l)"
        echo -e "${CYAN}Total files/entries in archive: $total_files${RESET}\n"
    fi
}

# =============================================================================
# MODULE 5 — RESTORE ARCHIVE
# =============================================================================
restore_archive() {
    log_section "Restore Files From Archive"

    read -rp "Enter path to archive to restore: " arc_file
    if [[ -z "$arc_file" || ! -f "$arc_file" ]]; then
        log_error "Archive file '$arc_file' does not exist."
        return 1
    fi

    log_info "Pre-flight integrity verification..."
    if ! tar -tf "$arc_file" >/dev/null 2>&1; then
        log_error "Archive integrity verification failed. Aborting restore."
        return 1
    fi
    log_success "Archive integrity verified."

    echo ""
    echo "Restore Destination Mode:"
    echo "  1) Restore to a Sandbox directory (Recommended: /tmp/restore_preview)"
    echo "  2) Restore to original root (/)"
    echo "  3) Custom destination path"
    read -rp "Select destination mode [1-3, default 1]: " dest_mode
    dest_mode="${dest_mode:-1}"

    local target_dest="/tmp/restore_preview"
    case "$dest_mode" in
        1) target_dest="/tmp/restore_preview" ;;
        2)
            log_warn "WARNING: Restoring directly to '/' may overwrite live system files!"
            read -rp "Type 'RESTORE' to confirm overwrite risk: " confirm_live
            if [[ "$confirm_live" != "RESTORE" ]]; then
                log_info "Restore canceled."
                return 0
            fi
            target_dest="/"
            ;;
        3)
            read -rp "Enter custom target directory path: " target_dest
            if [[ -z "$target_dest" ]]; then
                log_error "Target destination path cannot be empty."
                return 1
            fi
            ;;
        *) log_error "Invalid selection."; return 1 ;;
    esac

    mkdir -p "$target_dest"

    echo ""
    echo "Extraction Mode:"
    echo "  1) Extract entire archive"
    echo "  2) Extract a specific file or subfolder"
    read -rp "Select extraction mode [1-2, default 1]: " ext_mode
    ext_mode="${ext_mode:-1}"

    local specific_file=""
    if [[ "$ext_mode" == "2" ]]; then
        read -rp "Enter exact path of file/folder inside archive to extract: " specific_file
        if [[ -z "$specific_file" ]]; then
            log_error "Pattern cannot be empty."
            return 1
        fi
    fi

    log_info "Restoring to target directory: $target_dest"
    read -rp "Proceed with extraction? [Y/n]: " proceed_ext
    if [[ ! "${proceed_ext:-Y}" =~ ^[Yy] ]]; then
        log_info "Restore aborted by user."
        return 0
    fi

    local restore_cmd=("tar" "-xpf" "$arc_file" "-C" "$target_dest")
    if [[ -n "$specific_file" ]]; then
        restore_cmd+=("$specific_file")
    fi

    if "${restore_cmd[@]}"; then
        log_success "Extraction completed successfully!"
        log_info "Extracted contents are located in: ${BOLD}$target_dest${RESET}"
        audit "RESTORE" "ARCHIVE=$arc_file DEST=$target_dest SPECIFIC=${specific_file:-ALL}"
    else
        log_error "Extraction encountered errors."
        return 1
    fi
}

# =============================================================================
# MODULE 6 — BACKUP ROTATION & RETENTION POLICY
# =============================================================================
cleanup_old_backups() {
    log_section "Backup Retention & Rotation Policy"
    echo "Scan and purge archives exceeding a retention window (in days)."

    read -rp "Enter directory containing backups [default: /var/backups]: " backup_dir
    backup_dir="${backup_dir:-/var/backups}"
    if [[ ! -d "$backup_dir" ]]; then
        log_error "Directory '$backup_dir' does not exist."
        return 1
    fi

    read -rp "Enter retention period in days (e.g. 7, 14, 30): " retention_days
    if [[ ! "$retention_days" =~ ^[0-9]+$ ]] || [[ "$retention_days" -lt 1 ]]; then
        log_error "Retention days must be a positive integer."
        return 1
    fi

    log_info "Scanning '$backup_dir' for archive files older than $retention_days days..."

    # Find archives matching tar, tar.gz, tar.bz2, tar.xz, sha256
    local old_files
    old_files=$(find "$backup_dir" -maxdepth 2 -type f \( -name "*.tar*" -o -name "*.sha256" -o -name "*.snar" \) -mtime +"$retention_days")

    if [[ -z "$old_files" ]]; then
        log_success "No backup files found older than $retention_days days."
        return 0
    fi

    echo -e "\n${YELLOW}Files eligible for deletion:${RESET}"
    echo "$old_files" | while read -r f; do
        local mod_time
        mod_time="$(date -r "$f" '+%Y-%m-%d %H:%M:%S')"
        local f_size
        f_size="$(du -h "$f" | awk '{print $1}')"
        echo "  - $f ($f_size, last modified: $mod_time)"
    done

    echo ""
    read -rp "Permanently delete these files? Type 'DELETE' to confirm: " del_confirm
    if [[ "$del_confirm" == "DELETE" ]]; then
        local count=0
        while read -r f; do
            rm -f "$f"
            ((count++))
        done <<< "$old_files"
        log_success "Cleaned up $count old backup file(s)."
        audit "RETENTION_CLEANUP" "DIR=$backup_dir DAYS=$retention_days DELETED_COUNT=$count"
    else
        log_info "Deletion canceled. No files were removed."
    fi
}

# =============================================================================
# MODULE 7 — CRON SCHEDULER & AUTOMATED BACKUP GENERATOR
# =============================================================================
cron_job_helper() {
    log_section "Automated Scheduled Backup (Cron Integration)"
    require_cmd crontab || return 1

    echo "This wizard creates an automated backup script and schedules it via cron."
    read -rp "Enter directory/files to backup automatically: " auto_src
    if [[ -z "$auto_src" || ! -e "$auto_src" ]]; then
        log_error "Source path '$auto_src' is invalid."
        return 1
    fi
    auto_src="$(realpath "$auto_src")"

    read -rp "Enter destination backup directory [default: /var/backups]: " auto_dest
    auto_dest="${auto_dest:-/var/backups}"
    mkdir -p "$auto_dest"

    read -rp "Enter retention period in days [default: 14]: " auto_retention
    auto_retention="${auto_retention:-14}"

    local script_path="/usr/local/bin/auto_backup_${auto_src//\//_}.sh"
    # Clean double underscores
    script_path="${script_path//__/_}"

    log_info "Generating standalone automation script at: $script_path"

    cat << 'EOF' > "$script_path"
#!/usr/bin/env bash
# Auto-generated backup script by backup_restore.sh
set -euo pipefail

SRC="TARGET_SRC"
DEST="TARGET_DEST"
RETENTION=TARGET_RETENTION
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
BASE_NAME="$(basename "$SRC")"
ARCHIVE="${DEST}/${BASE_NAME}_auto_${TIMESTAMP}.tar.gz"

mkdir -p "$DEST"

# Create archive
parent_dir="$(dirname "$SRC")"
item_name="$(basename "$SRC")"
tar -p --numeric-owner -czf "$ARCHIVE" -C "$parent_dir" "$item_name"
sha256sum "$ARCHIVE" > "${ARCHIVE}.sha256"

# Cleanup archives older than retention threshold
find "$DEST" -maxdepth 1 -type f \( -name "${BASE_NAME}_auto_*.tar.gz" -o -name "${BASE_NAME}_auto_*.sha256" \) -mtime +"$RETENTION" -delete

logger -t auto_backup "Backup completed for $SRC into $ARCHIVE (retention: $RETENTION days)"
EOF

    # Replace placeholders
    sed -i "s|TARGET_SRC|$auto_src|g" "$script_path"
    sed -i "s|TARGET_DEST|$auto_dest|g" "$script_path"
    sed -i "s|TARGET_RETENTION|$auto_retention|g" "$script_path"
    chmod +x "$script_path"

    log_success "Automation script created and marked executable."

    echo ""
    echo "Choose schedule frequency:"
    echo "  1) Daily at 02:00 AM"
    echo "  2) Daily at midnight (00:00)"
    echo "  3) Weekly on Sunday at 03:00 AM"
    echo "  4) Hourly"
    echo "  5) Custom cron expression"
    read -rp "Select schedule [1-5, default 1]: " freq_opt
    freq_opt="${freq_opt:-1}"

    local cron_time="0 2 * * *"
    case "$freq_opt" in
        1) cron_time="0 2 * * *" ;;
        2) cron_time="0 0 * * *" ;;
        3) cron_time="0 3 * * 0" ;;
        4) cron_time="0 * * * *" ;;
        5)
            read -rp "Enter 5-part cron expression (e.g. '30 1 * * 1-5'): " cron_time
            if [[ -z "$cron_time" ]]; then
                log_error "Cron expression cannot be empty."
                return 1
            fi
            ;;
        *) cron_time="0 2 * * *" ;;
    esac

    local cron_line="$cron_time $script_path >/dev/null 2>&1"
    echo -e "\nProposed cron entry:\n  ${GREEN}$cron_line${RESET}\n"

    read -rp "Install this entry to root's crontab? [Y/n]: " add_cron
    if [[ "${add_cron:-Y}" =~ ^[Yy] ]]; then
        # Check if already in crontab
        local current_cron
        current_cron="$(crontab -l 2>/dev/null || true)"
        if echo "$current_cron" | grep -Fq "$script_path"; then
            log_warn "Crontab entry already exists for this script. Updating schedule..."
            current_cron="$(echo "$current_cron" | grep -Fv "$script_path")"
        fi
        (echo "$current_cron"; echo "$cron_line") | crontab -
        log_success "Crontab updated successfully!"
        audit "CRON_INSTALL" "SCRIPT=$script_path CRON=\"$cron_line\""
    else
        log_info "Crontab not modified. You can add the entry manually whenever you wish."
    fi
}

# =============================================================================
# MODULE 8 — CRITICAL SYSTEM STATE & CONFIGS SNAPSHOT
# =============================================================================
critical_system_snapshot() {
    log_section "Critical System Config & State Snapshot"
    echo "Rapidly packages /etc configurations, crontabs, user/group tables, and package manifests."

    read -rp "Enter destination backup directory [default: /var/backups/system_snapshots]: " snap_dest
    snap_dest="${snap_dest:-/var/backups/system_snapshots}"
    mkdir -p "$snap_dest"

    local timestamp
    timestamp="$(date +'%Y%m%d_%H%M%S')"
    local temp_snap_dir="/tmp/sys_snap_${timestamp}"
    mkdir -p "$temp_snap_dir"

    log_info "Gathering package manifest..."
    if command -v dpkg &>/dev/null; then
        dpkg --get-selections > "${temp_snap_dir}/dpkg_packages.txt" 2>/dev/null || true
    elif command -v rpm &>/dev/null; then
        rpm -qa --qf "%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n" | sort > "${temp_snap_dir}/rpm_packages.txt" 2>/dev/null || true
    elif command -v pacman &>/dev/null; then
        pacman -Qqe > "${temp_snap_dir}/pacman_packages.txt" 2>/dev/null || true
    fi

    log_info "Exporting crontabs and system metadata..."
    crontab -l > "${temp_snap_dir}/root_crontab.txt" 2>/dev/null || true
    uname -a > "${temp_snap_dir}/system_uname.txt"
    ip addr show > "${temp_snap_dir}/network_interfaces.txt" 2>/dev/null || true
    lsblk > "${temp_snap_dir}/storage_block_devices.txt" 2>/dev/null || true

    log_info "Copying core system configurations (/etc)..."
    tar --exclude="/etc/ca-certificates" -czf "${temp_snap_dir}/etc_config_bundle.tar.gz" /etc 2>/dev/null || true

    local final_archive="${snap_dest}/system_snapshot_${timestamp}.tar.gz"
    log_info "Bundling final snapshot into: $final_archive"
    tar -czf "$final_archive" -C "$temp_snap_dir" .
    rm -rf "$temp_snap_dir"

    sha256sum "$final_archive" > "${final_archive}.sha256"
    local snap_size
    snap_size="$(du -h "$final_archive" | awk '{print $1}')"

    log_success "System state snapshot completed! (Size: $snap_size)"
    log_info "Saved at: ${BOLD}$final_archive${RESET}"
    audit "SYSTEM_SNAPSHOT" "ARCHIVE=$final_archive SIZE=$snap_size"
}

# =============================================================================
# MODULE 9 — AUDIT LOG VIEWER
# =============================================================================
view_audit_log() {
    log_section "Audit Log — $AUDIT_LOG"
    if [[ -f "$AUDIT_LOG" ]]; then
        echo -e "${BOLD}Last 30 audit records:${RESET}"
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
        echo -e "${CYAN}${BOLD}║       Linux Backup & Restore Administration Tool v1.0         ║${RESET}"
        echo -e "${CYAN}${BOLD}║                     github.com/ACESVAGE                       ║${RESET}"
        echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════════╝${RESET}"
        echo ""
        echo "  1) Create Full Archive (tar + gzip/bzip2/xz with SHA-256)"
        echo "  2) Create Incremental Backup (tar snapshot / snar)"
        echo "  3) Synchronize / Mirror Directory (rsync with dry-run)"
        echo "  4) Verify Archive Integrity & Inspect Contents"
        echo "  5) Restore Files From Archive (sandbox or custom path)"
        echo "  6) Backup Retention & Cleanup (purge older than N days)"
        echo "  7) Automated Scheduled Backup (cron wizard)"
        echo "  8) Critical System Config & State Snapshot (/etc, pkgs, cron)"
        echo "  9) View Audit Log"
        echo " 10) Exit"
        echo ""
        read -rp "Select an option [1-10]: " choice

        case "$choice" in
            1)  create_full_archive ;;
            2)  create_incremental_backup ;;
            3)  rsync_mirror ;;
            4)  verify_and_inspect_archive ;;
            5)  restore_archive ;;
            6)  cleanup_old_backups ;;
            7)  cron_job_helper ;;
            8)  critical_system_snapshot ;;
            9)  view_audit_log ;;
            10) log_info "Exiting. Stay backed up & secure! 🛡️"; exit 0 ;;
            *)  log_error "Invalid option. Please choose a number between 1 and 10." ;;
        esac
    done
}

# =============================================================================
# ENTRY POINT
# =============================================================================
check_root
main_menu
