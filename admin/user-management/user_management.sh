#!/usr/bin/env bash
# =============================================================================
# user_management.sh â€” Linux User & Group Administration Tool
# =============================================================================
# Author      : ACESVAGE
# Repository  : https://github.com/ACESVAGE/linux-admin-scripts
# Description : Interactive menu-driven script for managing Linux users and
#               groups. Covers creation, deletion, modification, locking,
#               password policy, and group membership.
#
# Usage       : sudo ./user_management.sh
# Requirements: Must be run as root (or via sudo)
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

# â”€â”€ Audit log â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
AUDIT_LOG="/var/log/user_management_audit.log"

audit() {
    local action="$1"
    local target="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | USER=$(logname 2>/dev/null || echo root) | ACTION=$action | TARGET=$target" \
        >> "$AUDIT_LOG" 2>/dev/null || true
}

# =============================================================================
# SECTION 1 â€” USER CREATION
# =============================================================================
create_user() {
    log_section "Create New User"

    read -rp "Enter username to create: " username
    if [[ -z "$username" ]]; then
        log_error "Username cannot be empty."; return 1
    fi

    if id "$username" &>/dev/null; then
        log_warn "User '$username' already exists."; return 1
    fi

    read -rp "Enter full name (comment/GECOS) [optional]: " full_name
    read -rp "Enter home directory [default: /home/$username]: " home_dir
    home_dir="${home_dir:-/home/$username}"

    read -rp "Enter shell [default: /bin/bash]: " user_shell
    user_shell="${user_shell:-/bin/bash}"

    read -rp "Create a primary group with the same name? [Y/n]: " create_group
    create_group="${create_group:-Y}"

    # Build useradd command
    local cmd="useradd -m -d \"$home_dir\" -s \"$user_shell\""
    [[ -n "$full_name" ]] && cmd+=" -c \"$full_name\""
    [[ "${create_group,,}" == "y" ]] && cmd+=" -U"
    cmd+=" \"$username\""

    eval "$cmd"
    log_success "User '$username' created."

    # Set password
    read -rp "Set password now? [Y/n]: " set_pw
    set_pw="${set_pw:-Y}"
    if [[ "${set_pw,,}" == "y" ]]; then
        passwd "$username"
    else
        log_warn "No password set. Account is locked until a password is assigned."
    fi

    audit "CREATE_USER" "$username"
    log_success "User '$username' fully provisioned."
}

# =============================================================================
# SECTION 2 â€” USER DELETION
# =============================================================================
delete_user() {
    log_section "Delete User"

    read -rp "Enter username to delete: " username
    if ! id "$username" &>/dev/null; then
        log_error "User '$username' does not exist."; return 1
    fi

    read -rp "Remove home directory and mail spool? [y/N]: " remove_home
    remove_home="${remove_home:-N}"

    echo -e "${RED}WARNING: This action is irreversible.${RESET}"
    read -rp "Type the username again to confirm deletion: " confirm
    if [[ "$confirm" != "$username" ]]; then
        log_warn "Confirmation mismatch. Aborted."; return 1
    fi

    if [[ "${remove_home,,}" == "y" ]]; then
        userdel -r "$username"
        log_success "User '$username' and home directory removed."
    else
        userdel "$username"
        log_success "User '$username' removed (home directory preserved)."
    fi

    audit "DELETE_USER" "$username"
}

# =============================================================================
# SECTION 3 â€” MODIFY USER
# =============================================================================
modify_user() {
    log_section "Modify User"

    read -rp "Enter username to modify: " username
    if ! id "$username" &>/dev/null; then
        log_error "User '$username' does not exist."; return 1
    fi

    echo ""
    echo "  1) Change username (login name)"
    echo "  2) Change home directory"
    echo "  3) Change login shell"
    echo "  4) Change full name (GECOS)"
    echo "  5) Change password"
    echo "  6) Add to supplementary group(s)"
    echo "  7) Remove from a group"
    echo "  8) Back to main menu"
    echo ""
    read -rp "Choose option [1-8]: " mod_choice

    case "$mod_choice" in
        1)
            read -rp "Enter new username: " new_username
            usermod -l "$new_username" "$username"
            usermod -d "/home/$new_username" -m "$new_username"
            log_success "Username changed: '$username' â†’ '$new_username'"
            audit "RENAME_USER" "$username -> $new_username"
            ;;
        2)
            read -rp "Enter new home directory: " new_home
            read -rp "Move existing home contents? [Y/n]: " move_home
            move_home="${move_home:-Y}"
            if [[ "${move_home,,}" == "y" ]]; then
                usermod -d "$new_home" -m "$username"
            else
                usermod -d "$new_home" "$username"
            fi
            log_success "Home directory updated to '$new_home'."
            audit "CHANGE_HOME" "$username -> $new_home"
            ;;
        3)
            read -rp "Enter new shell (e.g. /bin/bash, /bin/zsh, /usr/bin/fish): " new_shell
            if ! grep -q "^$new_shell$" /etc/shells; then
                log_warn "'$new_shell' is not listed in /etc/shells. Proceeding anyway."
            fi
            usermod -s "$new_shell" "$username"
            log_success "Shell changed to '$new_shell'."
            audit "CHANGE_SHELL" "$username -> $new_shell"
            ;;
        4)
            read -rp "Enter new full name/GECOS: " new_gecos
            usermod -c "$new_gecos" "$username"
            log_success "GECOS updated."
            audit "CHANGE_GECOS" "$username"
            ;;
        5)
            passwd "$username"
            audit "CHANGE_PASSWORD" "$username"
            ;;
        6)
            read -rp "Enter group(s) to add (comma-separated): " groups
            usermod -aG "$groups" "$username"
            log_success "Added '$username' to group(s): $groups"
            audit "ADD_TO_GROUPS" "$username -> $groups"
            ;;
        7)
            read -rp "Enter group to remove '$username' from: " rem_group
            gpasswd -d "$username" "$rem_group"
            log_success "Removed '$username' from group '$rem_group'."
            audit "REMOVE_FROM_GROUP" "$username -> $rem_group"
            ;;
        8) return ;;
        *) log_error "Invalid option." ;;
    esac
}

# =============================================================================
# SECTION 4 â€” LOCK / UNLOCK ACCOUNT
# =============================================================================
lock_unlock_user() {
    log_section "Lock / Unlock Account"

    read -rp "Enter username: " username
    if ! id "$username" &>/dev/null; then
        log_error "User '$username' does not exist."; return 1
    fi

    echo "  1) Lock account"
    echo "  2) Unlock account"
    echo "  3) Expire account immediately (force login disabled)"
    echo "  4) Set account expiry date"
    echo ""
    read -rp "Choose option [1-4]: " lock_choice

    case "$lock_choice" in
        1)
            usermod -L "$username"
            log_success "Account '$username' locked."
            audit "LOCK_USER" "$username"
            ;;
        2)
            usermod -U "$username"
            log_success "Account '$username' unlocked."
            audit "UNLOCK_USER" "$username"
            ;;
        3)
            usermod --expiredate 1 "$username"
            log_success "Account '$username' expired (effectively disabled)."
            audit "EXPIRE_USER" "$username"
            ;;
        4)
            read -rp "Enter expiry date (YYYY-MM-DD): " exp_date
            usermod --expiredate "$exp_date" "$username"
            log_success "Account '$username' will expire on $exp_date."
            audit "SET_EXPIRY" "$username -> $exp_date"
            ;;
        *) log_error "Invalid option." ;;
    esac
}

# =============================================================================
# SECTION 5 â€” PASSWORD POLICY
# =============================================================================
password_policy() {
    log_section "Password Policy (chage)"

    read -rp "Enter username: " username
    if ! id "$username" &>/dev/null; then
        log_error "User '$username' does not exist."; return 1
    fi

    echo ""
    echo "Current password ageing info for '$username':"
    chage -l "$username"
    echo ""

    echo "  1) Set maximum password age (days)"
    echo "  2) Set minimum password age (days)"
    echo "  3) Set warning days before expiry"
    echo "  4) Force password change on next login"
    echo "  5) Set all policies interactively"
    echo ""
    read -rp "Choose option [1-5]: " pw_choice

    case "$pw_choice" in
        1)
            read -rp "Max days before password must be changed: " max_days
            chage -M "$max_days" "$username"
            log_success "Max password age set to $max_days days."
            audit "PW_MAX_AGE" "$username -> $max_days days"
            ;;
        2)
            read -rp "Min days between password changes: " min_days
            chage -m "$min_days" "$username"
            log_success "Min password age set to $min_days days."
            audit "PW_MIN_AGE" "$username -> $min_days days"
            ;;
        3)
            read -rp "Days warning before password expires: " warn_days
            chage -W "$warn_days" "$username"
            log_success "Warning period set to $warn_days days."
            audit "PW_WARN_DAYS" "$username -> $warn_days days"
            ;;
        4)
            chage -d 0 "$username"
            log_success "User '$username' must change password on next login."
            audit "FORCE_PW_CHANGE" "$username"
            ;;
        5)
            chage "$username"
            audit "PW_POLICY_INTERACTIVE" "$username"
            ;;
        *) log_error "Invalid option." ;;
    esac
}

# =============================================================================
# SECTION 6 â€” GROUP MANAGEMENT
# =============================================================================
group_management() {
    log_section "Group Management"

    echo "  1) Create new group"
    echo "  2) Delete group"
    echo "  3) List all groups"
    echo "  4) List members of a group"
    echo "  5) List groups a user belongs to"
    echo ""
    read -rp "Choose option [1-5]: " grp_choice

    case "$grp_choice" in
        1)
            read -rp "Enter new group name: " grp_name
            if getent group "$grp_name" &>/dev/null; then
                log_warn "Group '$grp_name' already exists."; return 1
            fi
            read -rp "Specify GID? (leave blank for auto): " grp_gid
            if [[ -n "$grp_gid" ]]; then
                groupadd -g "$grp_gid" "$grp_name"
            else
                groupadd "$grp_name"
            fi
            log_success "Group '$grp_name' created."
            audit "CREATE_GROUP" "$grp_name"
            ;;
        2)
            read -rp "Enter group name to delete: " grp_name
            if ! getent group "$grp_name" &>/dev/null; then
                log_error "Group '$grp_name' does not exist."; return 1
            fi
            groupdel "$grp_name"
            log_success "Group '$grp_name' deleted."
            audit "DELETE_GROUP" "$grp_name"
            ;;
        3)
            log_section "All System Groups"
            getent group | sort | awk -F: '{printf "%-20s GID: %-6s Members: %s\n", $1, $3, $4}'
            ;;
        4)
            read -rp "Enter group name: " grp_name
            if ! getent group "$grp_name" &>/dev/null; then
                log_error "Group '$grp_name' does not exist."; return 1
            fi
            log_section "Members of '$grp_name'"
            getent group "$grp_name" | awk -F: '{print $4}' | tr ',' '\n' | sort
            ;;
        5)
            read -rp "Enter username: " username
            if ! id "$username" &>/dev/null; then
                log_error "User '$username' does not exist."; return 1
            fi
            log_section "Groups for '$username'"
            id "$username"
            groups "$username"
            ;;
        *) log_error "Invalid option." ;;
    esac
}

# =============================================================================
# SECTION 7 â€” LIST & VIEW USERS
# =============================================================================
list_users() {
    log_section "System Users"

    echo ""
    echo "  1) List all users (human/login accounts, UID â‰¥ 1000)"
    echo "  2) List ALL users (including system accounts)"
    echo "  3) View detailed info for a specific user"
    echo "  4) List currently logged-in users"
    echo "  5) Show last login times"
    echo ""
    read -rp "Choose option [1-5]: " list_choice

    case "$list_choice" in
        1)
            log_section "Login Accounts (UID â‰¥ 1000)"
            awk -F: '$3 >= 1000 && $3 != 65534 {printf "%-20s UID: %-6s Home: %s\n", $1, $3, $6}' /etc/passwd | sort
            ;;
        2)
            log_section "All System Accounts"
            awk -F: '{printf "%-20s UID: %-6s Shell: %s\n", $1, $3, $7}' /etc/passwd | sort -t: -k3 -n
            ;;
        3)
            read -rp "Enter username: " username
            if ! id "$username" &>/dev/null; then
                log_error "User '$username' does not exist."; return 1
            fi
            log_section "User Info: $username"
            echo -e "${BOLD}Identity:${RESET}"
            id "$username"
            echo ""
            echo -e "${BOLD}/etc/passwd entry:${RESET}"
            grep "^$username:" /etc/passwd
            echo ""
            echo -e "${BOLD}Password status:${RESET}"
            passwd -S "$username" 2>/dev/null || echo "(run as root for full details)"
            echo ""
            echo -e "${BOLD}Password ageing:${RESET}"
            chage -l "$username" 2>/dev/null || echo "(run as root for full details)"
            ;;
        4)
            log_section "Currently Logged-In Users"
            who
            echo ""
            w
            ;;
        5)
            log_section "Last Login Times"
            lastlog | grep -v "Never logged in" | head -40
            ;;
        *) log_error "Invalid option." ;;
    esac
}

# =============================================================================
# SECTION 8 â€” SUDO MANAGEMENT
# =============================================================================
sudo_management() {
    log_section "Sudo / Privilege Management"

    echo "  1) Grant sudo privileges to user"
    echo "  2) Revoke sudo privileges from user"
    echo "  3) List all users with sudo access"
    echo ""
    read -rp "Choose option [1-3]: " sudo_choice

    case "$sudo_choice" in
        1)
            read -rp "Enter username to grant sudo: " username
            if ! id "$username" &>/dev/null; then
                log_error "User '$username' does not exist."; return 1
            fi
            # Works on both Debian/Ubuntu (sudo group) and RHEL/CentOS (wheel group)
            if getent group sudo &>/dev/null; then
                usermod -aG sudo "$username"
                log_success "Added '$username' to 'sudo' group."
            elif getent group wheel &>/dev/null; then
                usermod -aG wheel "$username"
                log_success "Added '$username' to 'wheel' group."
            else
                log_error "Neither 'sudo' nor 'wheel' group found. Check your distro's sudo setup."
                return 1
            fi
            audit "GRANT_SUDO" "$username"
            ;;
        2)
            read -rp "Enter username to revoke sudo: " username
            if ! id "$username" &>/dev/null; then
                log_error "User '$username' does not exist."; return 1
            fi
            if getent group sudo &>/dev/null; then
                gpasswd -d "$username" sudo
            elif getent group wheel &>/dev/null; then
                gpasswd -d "$username" wheel
            fi
            log_success "Sudo privileges revoked from '$username'."
            audit "REVOKE_SUDO" "$username"
            ;;
        3)
            log_section "Users with Sudo Access"
            echo -e "${BOLD}Members of 'sudo' group:${RESET}"
            getent group sudo 2>/dev/null | awk -F: '{print $4}' | tr ',' '\n' | sort || echo "  (group not found)"
            echo ""
            echo -e "${BOLD}Members of 'wheel' group:${RESET}"
            getent group wheel 2>/dev/null | awk -F: '{print $4}' | tr ',' '\n' | sort || echo "  (group not found)"
            echo ""
            echo -e "${BOLD}Custom /etc/sudoers entries (non-default):${RESET}"
            grep -v '^#' /etc/sudoers 2>/dev/null | grep -v '^$' | grep -v '^Defaults' | grep -v '^root' | grep -v '%' || echo "  (none)"
            ;;
        *) log_error "Invalid option." ;;
    esac
}

# =============================================================================
# MAIN MENU
# =============================================================================
main_menu() {
    while true; do
        echo ""
        echo -e "${CYAN}${BOLD}â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—${RESET}"
        echo -e "${CYAN}${BOLD}â•‘       Linux User Management Tool v1.0        â•‘${RESET}"
        echo -e "${CYAN}${BOLD}â•‘         github.com/ACESVAGE                  â•‘${RESET}"
        echo -e "${CYAN}${BOLD}â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${RESET}"
        echo ""
        echo "  1) Create user"
        echo "  2) Delete user"
        echo "  3) Modify user"
        echo "  4) Lock / Unlock account"
        echo "  5) Password policy"
        echo "  6) Group management"
        echo "  7) List / View users"
        echo "  8) Sudo management"
        echo "  9) View audit log"
        echo " 10) Exit"
        echo ""
        read -rp "Select an option [1-10]: " choice

        case "$choice" in
            1)  create_user ;;
            2)  delete_user ;;
            3)  modify_user ;;
            4)  lock_unlock_user ;;
            5)  password_policy ;;
            6)  group_management ;;
            7)  list_users ;;
            8)  sudo_management ;;
            9)
                log_section "Audit Log â€” $AUDIT_LOG"
                if [[ -f "$AUDIT_LOG" ]]; then
                    tail -50 "$AUDIT_LOG"
                else
                    log_warn "No audit log found yet."
                fi
                ;;
           10)  log_info "Exiting. Stay secure! ðŸ›¡ï¸"; exit 0 ;;
            *)  log_error "Invalid option. Choose 1â€“10." ;;
        esac
    done
}

# =============================================================================
# ENTRY POINT
# =============================================================================
check_root
main_menu
