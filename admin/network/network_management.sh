#!/usr/bin/env bash
# =============================================================================
# network_management.sh â€” Linux Network Administration & Diagnostics Tool
# =============================================================================
# Author      : ACESVAGE
# Repository  : https://github.com/ACESVAGE/linux-admin-scripts
# Description : Interactive menu-driven script for managing and diagnosing
#               Linux networking. Covers interface config, connectivity tests,
#               DNS, firewall, open ports, bandwidth monitoring, and more.
#
# Usage       : sudo ./network_management.sh
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
    if ! command -v "$1" &>/dev/null; then
        log_warn "'$1' not found. Install it with: apt install $2 / yum install $2"
        return 1
    fi
}

# â”€â”€ Audit log â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
AUDIT_LOG="/var/log/network_management_audit.log"

audit() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | USER=$(logname 2>/dev/null || echo root) | ACTION=$1 | DETAIL=$2" \
        >> "$AUDIT_LOG" 2>/dev/null || true
}

# =============================================================================
# SECTION 1 â€” NETWORK INTERFACE OVERVIEW
# =============================================================================
interface_overview() {
    log_section "Network Interface Overview"

    echo ""
    echo -e "${BOLD}â”€â”€ IP Addresses & Interfaces (ip addr) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€${RESET}"
    ip -c addr show 2>/dev/null || ifconfig 2>/dev/null || log_warn "Neither 'ip' nor 'ifconfig' found."

    echo ""
    echo -e "${BOLD}â”€â”€ Routing Table (ip route) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€${RESET}"
    ip route show 2>/dev/null || netstat -rn 2>/dev/null

    echo ""
    echo -e "${BOLD}â”€â”€ Network Interfaces Summary â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€${RESET}"
    ip -s link show 2>/dev/null | grep -E "^[0-9]+:|RX:|TX:|bytes" | \
        awk '/^[0-9]+:/{iface=$2} /RX:/{getline; rx=$1} /TX:/{getline; tx=$1; printf "%-20s RX: %-15s TX: %s\n", iface, rx, tx}'

    audit "INTERFACE_OVERVIEW" "ran"
}

# =============================================================================
# SECTION 2 â€” INTERFACE MANAGEMENT
# =============================================================================
interface_management() {
    log_section "Interface Management"

    echo "  1) Bring interface UP"
    echo "  2) Bring interface DOWN"
    echo "  3) Restart network service"
    echo "  4) Assign static IP to interface"
    echo "  5) Release & renew DHCP lease"
    echo "  6) Show interface statistics"
    echo ""
    read -rp "Choose option [1-6]: " iface_choice

    case "$iface_choice" in
        1)
            read -rp "Interface name (e.g. eth0, ens33): " iface
            ip link set "$iface" up
            log_success "Interface '$iface' is UP."
            audit "IFACE_UP" "$iface"
            ;;
        2)
            read -rp "Interface name: " iface
            ip link set "$iface" down
            log_success "Interface '$iface' is DOWN."
            audit "IFACE_DOWN" "$iface"
            ;;
        3)
            if systemctl is-active --quiet NetworkManager; then
                systemctl restart NetworkManager
                log_success "NetworkManager restarted."
            elif systemctl is-active --quiet networking; then
                systemctl restart networking
                log_success "networking service restarted."
            else
                log_warn "Could not detect network service. Try: systemctl restart NetworkManager"
            fi
            audit "NETWORK_RESTART" "done"
            ;;
        4)
            read -rp "Interface name: " iface
            read -rp "IP address (e.g. 192.168.1.100): " ip_addr
            read -rp "Subnet prefix (e.g. 24 for /24): " prefix
            read -rp "Gateway (e.g. 192.168.1.1): " gateway

            ip addr flush dev "$iface"
            ip addr add "${ip_addr}/${prefix}" dev "$iface"
            ip route add default via "$gateway" dev "$iface" 2>/dev/null || true
            log_success "Static IP $ip_addr/$prefix assigned to '$iface', gateway $gateway."
            audit "STATIC_IP" "$iface -> $ip_addr/$prefix gw $gateway"
            ;;
        5)
            read -rp "Interface name: " iface
            log_info "Releasing DHCP lease on '$iface'..."
            dhclient -r "$iface" 2>/dev/null || true
            log_info "Requesting new DHCP lease..."
            dhclient "$iface" 2>/dev/null || log_warn "dhclient not found. Try: dhcpcd $iface"
            log_success "DHCP lease renewed on '$iface'."
            ip addr show "$iface"
            audit "DHCP_RENEW" "$iface"
            ;;
        6)
            read -rp "Interface name: " iface
            log_section "Stats for $iface"
            ip -s link show "$iface"
            cat "/sys/class/net/${iface}/statistics/rx_bytes" 2>/dev/null | \
                awk '{printf "RX bytes: %d (%.2f MB)\n", $1, $1/1024/1024}' || true
            cat "/sys/class/net/${iface}/statistics/tx_bytes" 2>/dev/null | \
                awk '{printf "TX bytes: %d (%.2f MB)\n", $1, $1/1024/1024}' || true
            audit "IFACE_STATS" "$iface"
            ;;
        *)
            log_error "Invalid option."
            ;;
    esac
}

# =============================================================================
# SECTION 3 â€” CONNECTIVITY TESTS
# =============================================================================
connectivity_tests() {
    log_section "Connectivity Tests"

    echo "  1) Ping a host"
    echo "  2) Traceroute to a host"
    echo "  3) Test internet connectivity"
    echo "  4) HTTP/HTTPS reachability check (curl)"
    echo "  5) Check latency to multiple targets"
    echo ""
    read -rp "Choose option [1-5]: " conn_choice

    case "$conn_choice" in
        1)
            read -rp "Host/IP to ping: " ping_host
            read -rp "Number of packets [default: 5]: " ping_count
            ping_count="${ping_count:-5}"
            ping -c "$ping_count" "$ping_host"
            audit "PING" "$ping_host x$ping_count"
            ;;
        2)
            read -rp "Host/IP for traceroute: " trace_host
            if command -v traceroute &>/dev/null; then
                traceroute "$trace_host"
            elif command -v tracepath &>/dev/null; then
                tracepath "$trace_host"
            else
                log_warn "Neither traceroute nor tracepath found. Install: apt install traceroute"
            fi
            audit "TRACEROUTE" "$trace_host"
            ;;
        3)
            log_info "Testing internet connectivity..."
            local targets=("8.8.8.8" "1.1.1.1" "google.com")
            for target in "${targets[@]}"; do
                if ping -c 1 -W 2 "$target" &>/dev/null; then
                    echo -e "  ${GREEN}âœ”${RESET} $target â€” reachable"
                else
                    echo -e "  ${RED}âœ˜${RESET} $target â€” unreachable"
                fi
            done
            audit "INTERNET_CHECK" "done"
            ;;
        4)
            read -rp "URL to test (e.g. https://google.com): " curl_url
            if require_cmd curl curl; then
                local http_code
                http_code=$(curl -o /dev/null -s -w "%{http_code}" --connect-timeout 5 "$curl_url")
                local time_total
                time_total=$(curl -o /dev/null -s -w "%{time_total}" --connect-timeout 5 "$curl_url")
                echo ""
                echo -e "  URL        : $curl_url"
                echo -e "  HTTP Code  : ${BOLD}$http_code${RESET}"
                echo -e "  Total Time : ${time_total}s"
                [[ "$http_code" -ge 200 && "$http_code" -lt 400 ]] && \
                    log_success "URL is reachable." || log_warn "URL returned HTTP $http_code"
            fi
            audit "HTTP_CHECK" "$curl_url"
            ;;
        5)
            local targets=("8.8.8.8" "1.1.1.1" "8.8.4.4" "9.9.9.9" "208.67.222.222")
            log_section "Latency Test Results"
            printf "%-25s %-15s %-15s %s\n" "Target" "Min (ms)" "Avg (ms)" "Max (ms)"
            echo "â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€"
            for target in "${targets[@]}"; do
                local result
                result=$(ping -c 4 -q "$target" 2>/dev/null | grep -oP '(?<=rtt min/avg/max/mdev = )[\d.]+/[\d.]+/[\d.]+' || echo "N/A")
                if [[ "$result" == "N/A" ]]; then
                    printf "%-25s %-15s %-15s %s\n" "$target" "N/A" "N/A" "N/A"
                else
                    IFS='/' read -r mn avg mx <<< "$result"
                    printf "%-25s %-15s %-15s %s\n" "$target" "$mn" "$avg" "$mx"
                fi
            done
            audit "LATENCY_TEST" "multi-target"
            ;;
        *)
            log_error "Invalid option."
            ;;
    esac
}

# =============================================================================
# SECTION 4 â€” DNS TOOLS
# =============================================================================
dns_tools() {
    log_section "DNS Tools"

    echo "  1) DNS lookup (nslookup / dig)"
    echo "  2) Reverse DNS lookup"
    echo "  3) Show current DNS servers"
    echo "  4) Change DNS servers"
    echo "  5) Flush DNS cache"
    echo "  6) Check DNS propagation for a domain"
    echo ""
    read -rp "Choose option [1-6]: " dns_choice

    case "$dns_choice" in
        1)
            read -rp "Domain to look up: " dns_domain
            if command -v dig &>/dev/null; then
                dig "$dns_domain" ANY +short
                echo ""
                log_info "Full A record:"
                dig "$dns_domain" A +noall +answer
            elif command -v nslookup &>/dev/null; then
                nslookup "$dns_domain"
            else
                log_warn "Neither dig nor nslookup found. Install: apt install dnsutils"
            fi
            audit "DNS_LOOKUP" "$dns_domain"
            ;;
        2)
            read -rp "IP address for reverse lookup: " rev_ip
            if command -v dig &>/dev/null; then
                dig -x "$rev_ip" +short
            else
                host "$rev_ip" 2>/dev/null || nslookup "$rev_ip"
            fi
            audit "REVERSE_DNS" "$rev_ip"
            ;;
        3)
            log_section "Current DNS Configuration"
            echo -e "${BOLD}/etc/resolv.conf:${RESET}"
            cat /etc/resolv.conf | grep -v "^#\|^$"
            echo ""
            if command -v resolvectl &>/dev/null; then
                echo -e "${BOLD}resolvectl status:${RESET}"
                resolvectl status | grep -E "DNS Servers|DNS Domain|Link" | head -20
            fi
            ;;
        4)
            read -rp "Primary DNS server (e.g. 8.8.8.8): " dns1
            read -rp "Secondary DNS server (e.g. 8.8.4.4): " dns2
            log_warn "This will overwrite /etc/resolv.conf. Some systems manage this automatically."
            read -rp "Proceed? [y/N]: " dns_confirm
            if [[ "${dns_confirm,,}" == "y" ]]; then
                cp /etc/resolv.conf /etc/resolv.conf.bak."$(date +%Y%m%d%H%M%S)"
                {
                    echo "# Generated by network_management.sh â€” $(date)"
                    echo "nameserver $dns1"
                    [[ -n "$dns2" ]] && echo "nameserver $dns2"
                    echo "options edns0"
                } > /etc/resolv.conf
                log_success "DNS servers updated. Backup saved."
                audit "CHANGE_DNS" "$dns1, $dns2"
            fi
            ;;
        5)
            log_info "Flushing DNS cache..."
            if command -v resolvectl &>/dev/null; then
                resolvectl flush-caches
                log_success "systemd-resolved cache flushed."
            elif command -v systemd-resolve &>/dev/null; then
                systemd-resolve --flush-caches
                log_success "DNS cache flushed."
            elif command -v nscd &>/dev/null; then
                service nscd restart
                log_success "nscd cache flushed."
            else
                log_warn "No supported DNS cache manager found."
            fi
            audit "DNS_FLUSH" "done"
            ;;
        6)
            read -rp "Domain to check: " prop_domain
            local servers=("8.8.8.8" "1.1.1.1" "9.9.9.9" "208.67.222.222" "64.6.64.6")
            log_section "DNS Propagation Check: $prop_domain"
            printf "%-20s %s\n" "DNS Server" "Result"
            echo "â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€"
            for srv in "${servers[@]}"; do
                local result
                result=$(dig "@$srv" "$prop_domain" A +short 2>/dev/null | head -1 || echo "N/A")
                printf "%-20s %s\n" "$srv" "${result:-NXDOMAIN}"
            done
            audit "DNS_PROPAGATION" "$prop_domain"
            ;;
        *)
            log_error "Invalid option."
            ;;
    esac
}

# =============================================================================
# SECTION 5 â€” OPEN PORTS & CONNECTIONS
# =============================================================================
ports_and_connections() {
    log_section "Open Ports & Active Connections"

    echo "  1) Show all listening ports"
    echo "  2) Show all active connections"
    echo "  3) Find which process owns a port"
    echo "  4) Show connection count by state"
    echo "  5) Watch live connections (continuous)"
    echo ""
    read -rp "Choose option [1-5]: " port_choice

    case "$port_choice" in
        1)
            log_section "Listening Ports"
            if command -v ss &>/dev/null; then
                ss -tlnup | column -t
            else
                netstat -tlnup 2>/dev/null | column -t
            fi
            audit "LISTENING_PORTS" "ran"
            ;;
        2)
            log_section "Active Connections"
            if command -v ss &>/dev/null; then
                ss -tunap | column -t
            else
                netstat -tunap 2>/dev/null | column -t
            fi
            audit "ACTIVE_CONNECTIONS" "ran"
            ;;
        3)
            read -rp "Port number to investigate: " port_num
            log_section "Process on port $port_num"
            if command -v ss &>/dev/null; then
                ss -tlnup "sport = :$port_num" || true
            fi
            lsof -i ":$port_num" 2>/dev/null || log_warn "lsof not found. Install: apt install lsof"
            fuser "$port_num/tcp" 2>/dev/null || true
            audit "PORT_LOOKUP" "$port_num"
            ;;
        4)
            log_section "Connection Count by State"
            if command -v ss &>/dev/null; then
                ss -tan | awk 'NR>1 {print $1}' | sort | uniq -c | sort -rn
            else
                netstat -tan 2>/dev/null | awk 'NR>2 {print $6}' | sort | uniq -c | sort -rn
            fi
            audit "CONN_BY_STATE" "ran"
            ;;
        5)
            log_info "Watching connections every 2s â€” press Ctrl+C to stop."
            watch -n 2 "ss -tunap | column -t"
            ;;
        *)
            log_error "Invalid option."
            ;;
    esac
}

# =============================================================================
# SECTION 6 â€” FIREWALL MANAGEMENT
# =============================================================================
firewall_management() {
    log_section "Firewall Management"

    # Detect available firewall
    local fw=""
    command -v ufw &>/dev/null      && fw="ufw"
    command -v firewall-cmd &>/dev/null && fw="firewalld"
    command -v iptables &>/dev/null && [[ -z "$fw" ]] && fw="iptables"

    log_info "Detected firewall: ${fw:-none}"
    echo ""

    echo "  1) Show firewall status / rules"
    echo "  2) Allow a port"
    echo "  3) Deny/block a port"
    echo "  4) Allow an IP address"
    echo "  5) Block an IP address"
    echo "  6) Enable firewall"
    echo "  7) Disable firewall"
    echo ""
    read -rp "Choose option [1-7]: " fw_choice

    case "$fw_choice" in
        1)
            case "$fw" in
                ufw)       ufw status verbose ;;
                firewalld) firewall-cmd --list-all ;;
                iptables)  iptables -L -v -n --line-numbers ;;
                *)         log_warn "No supported firewall detected." ;;
            esac
            ;;
        2)
            read -rp "Port to allow (e.g. 80, 443, 22/tcp): " fw_port
            case "$fw" in
                ufw)       ufw allow "$fw_port"; log_success "Port $fw_port allowed." ;;
                firewalld) firewall-cmd --permanent --add-port="$fw_port"; firewall-cmd --reload ;;
                iptables)  iptables -A INPUT -p tcp --dport "$fw_port" -j ACCEPT; log_success "iptables rule added." ;;
                *)         log_warn "No firewall found." ;;
            esac
            audit "FW_ALLOW_PORT" "$fw_port"
            ;;
        3)
            read -rp "Port to deny (e.g. 8080): " fw_port
            case "$fw" in
                ufw)       ufw deny "$fw_port"; log_success "Port $fw_port blocked." ;;
                firewalld) firewall-cmd --permanent --remove-port="$fw_port"; firewall-cmd --reload ;;
                iptables)  iptables -A INPUT -p tcp --dport "$fw_port" -j DROP; log_success "iptables DROP rule added." ;;
                *)         log_warn "No firewall found." ;;
            esac
            audit "FW_DENY_PORT" "$fw_port"
            ;;
        4)
            read -rp "IP address to allow: " fw_ip
            case "$fw" in
                ufw)       ufw allow from "$fw_ip"; log_success "IP $fw_ip allowed." ;;
                firewalld) firewall-cmd --permanent --add-source="$fw_ip"; firewall-cmd --reload ;;
                iptables)  iptables -A INPUT -s "$fw_ip" -j ACCEPT; log_success "iptables rule added." ;;
                *)         log_warn "No firewall found." ;;
            esac
            audit "FW_ALLOW_IP" "$fw_ip"
            ;;
        5)
            read -rp "IP address to block: " fw_ip
            case "$fw" in
                ufw)       ufw deny from "$fw_ip"; log_success "IP $fw_ip blocked." ;;
                firewalld) firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='$fw_ip' reject"; firewall-cmd --reload ;;
                iptables)  iptables -A INPUT -s "$fw_ip" -j DROP; log_success "iptables DROP rule added." ;;
                *)         log_warn "No firewall found." ;;
            esac
            audit "FW_BLOCK_IP" "$fw_ip"
            ;;
        6)
            case "$fw" in
                ufw)       ufw --force enable; log_success "UFW enabled." ;;
                firewalld) systemctl enable --now firewalld; log_success "firewalld enabled." ;;
                iptables)  log_warn "Enable iptables persistence via: apt install iptables-persistent" ;;
                *)         log_warn "No firewall found." ;;
            esac
            audit "FW_ENABLE" "$fw"
            ;;
        7)
            log_warn "Disabling your firewall exposes the system!"
            read -rp "Are you sure? [y/N]: " fw_dis_confirm
            if [[ "${fw_dis_confirm,,}" == "y" ]]; then
                case "$fw" in
                    ufw)       ufw disable; log_success "UFW disabled." ;;
                    firewalld) systemctl disable --now firewalld; log_success "firewalld disabled." ;;
                    iptables)  iptables -F; log_success "iptables rules flushed." ;;
                    *)         log_warn "No firewall found." ;;
                esac
                audit "FW_DISABLE" "$fw"
            fi
            ;;
        *)
            log_error "Invalid option."
            ;;
    esac
}

# =============================================================================
# SECTION 7 â€” BANDWIDTH & TRAFFIC MONITORING
# =============================================================================
bandwidth_monitoring() {
    log_section "Bandwidth & Traffic Monitoring"

    echo "  1) Live bandwidth monitor (iftop)"
    echo "  2) Per-interface traffic stats (nload)"
    echo "  3) Network I/O snapshot (ip -s link)"
    echo "  4) Show top bandwidth-consuming processes (nethogs)"
    echo "  5) Manual bandwidth calculation (bytes/sec)"
    echo ""
    read -rp "Choose option [1-5]: " bw_choice

    case "$bw_choice" in
        1)
            if require_cmd iftop iftop; then
                read -rp "Interface to monitor [default: auto]: " bw_iface
                if [[ -n "$bw_iface" ]]; then
                    iftop -i "$bw_iface"
                else
                    iftop
                fi
            fi
            ;;
        2)
            if require_cmd nload nload; then
                nload
            fi
            ;;
        3)
            log_section "Network I/O Snapshot"
            ip -s link show | grep -E "^[0-9]+:|RX|TX|bytes" | \
                awk '
                    /^[0-9]+:/ { iface=$2 }
                    /RX:/ { getline; rx=$1 }
                    /TX:/ { getline; printf "%-20s RX: %10d bytes  TX: %10d bytes\n", iface, rx, $1 }
                '
            ;;
        4)
            if require_cmd nethogs nethogs; then
                read -rp "Interface [default: auto]: " bw_iface
                nethogs "${bw_iface:-}"
            fi
            ;;
        5)
            read -rp "Interface name: " bw_iface
            log_info "Sampling traffic on '$bw_iface' for 5 seconds..."
            local rx1 tx1 rx2 tx2
            rx1=$(cat "/sys/class/net/${bw_iface}/statistics/rx_bytes" 2>/dev/null || echo 0)
            tx1=$(cat "/sys/class/net/${bw_iface}/statistics/tx_bytes" 2>/dev/null || echo 0)
            sleep 5
            rx2=$(cat "/sys/class/net/${bw_iface}/statistics/rx_bytes" 2>/dev/null || echo 0)
            tx2=$(cat "/sys/class/net/${bw_iface}/statistics/tx_bytes" 2>/dev/null || echo 0)
            local rx_rate tx_rate
            rx_rate=$(( (rx2 - rx1) / 5 ))
            tx_rate=$(( (tx2 - tx1) / 5 ))
            echo ""
            printf "  Download : %d bytes/s  (%.2f KB/s  /  %.2f Mbps)\n" \
                "$rx_rate" "$(echo "$rx_rate/1024" | bc -l)" "$(echo "$rx_rate*8/1000000" | bc -l)"
            printf "  Upload   : %d bytes/s  (%.2f KB/s  /  %.2f Mbps)\n" \
                "$tx_rate" "$(echo "$tx_rate/1024" | bc -l)" "$(echo "$tx_rate*8/1000000" | bc -l)"
            audit "BW_CALC" "$bw_iface"
            ;;
        *)
            log_error "Invalid option."
            ;;
    esac
}

# =============================================================================
# SECTION 8 â€” NETWORK SCANNING (LOCAL)
# =============================================================================
network_scanning() {
    log_section "Network Scanning (Local / Authorized Use Only)"

    echo -e "${YELLOW}âš   Only scan networks you own or have explicit permission to test.${RESET}"
    echo ""
    echo "  1) Discover live hosts on local subnet (nmap ping sweep)"
    echo "  2) Quick port scan on a single host"
    echo "  3) Show ARP table (local LAN devices)"
    echo "  4) Check if a specific port is open on a remote host"
    echo ""
    read -rp "Choose option [1-4]: " scan_choice

    case "$scan_choice" in
        1)
            read -rp "Subnet (e.g. 192.168.1.0/24): " subnet
            if require_cmd nmap nmap; then
                log_info "Ping sweeping $subnet..."
                nmap -sn "$subnet" --open | grep -E "Nmap scan|Host is up|report for"
            else
                log_info "Using arp-scan fallback..."
                arp-scan --localnet 2>/dev/null | grep -v "^Starting\|^Interface\|packets\|responded" || \
                    log_warn "Install nmap or arp-scan: apt install nmap"
            fi
            audit "HOST_DISCOVERY" "$subnet"
            ;;
        2)
            read -rp "Target host/IP: " scan_host
            read -rp "Port range [default: 1-1024]: " port_range
            port_range="${port_range:-1-1024}"
            if require_cmd nmap nmap; then
                nmap -sV --open -p "$port_range" "$scan_host"
            fi
            audit "PORT_SCAN" "$scan_host ports=$port_range"
            ;;
        3)
            log_section "ARP Table (Local LAN)"
            arp -n 2>/dev/null | column -t || \
            ip neigh show | column -t
            ;;
        4)
            read -rp "Remote host/IP: " remote_host
            read -rp "Port number: " remote_port
            if timeout 3 bash -c ">/dev/tcp/$remote_host/$remote_port" 2>/dev/null; then
                log_success "Port $remote_port on $remote_host is OPEN."
            else
                log_warn "Port $remote_port on $remote_host is CLOSED or FILTERED."
            fi
            audit "PORT_CHECK" "$remote_host:$remote_port"
            ;;
        *)
            log_error "Invalid option."
            ;;
    esac
}

# =============================================================================
# SECTION 9 â€” HOSTNAME & HOSTS FILE
# =============================================================================
hostname_management() {
    log_section "Hostname & Hosts File"

    echo "  1) Show current hostname info"
    echo "  2) Change hostname"
    echo "  3) View /etc/hosts"
    echo "  4) Add entry to /etc/hosts"
    echo "  5) Remove entry from /etc/hosts"
    echo ""
    read -rp "Choose option [1-5]: " host_choice

    case "$host_choice" in
        1)
            echo -e "${BOLD}Hostname:${RESET}     $(hostname)"
            echo -e "${BOLD}FQDN:${RESET}         $(hostname -f 2>/dev/null || echo 'N/A')"
            echo -e "${BOLD}Short:${RESET}         $(hostname -s 2>/dev/null || echo 'N/A')"
            hostnamectl 2>/dev/null || true
            ;;
        2)
            read -rp "New hostname: " new_hostname
            hostnamectl set-hostname "$new_hostname" 2>/dev/null || hostname "$new_hostname"
            log_success "Hostname changed to '$new_hostname'. Update /etc/hosts if needed."
            audit "CHANGE_HOSTNAME" "$new_hostname"
            ;;
        3)
            log_section "/etc/hosts"
            cat -n /etc/hosts
            ;;
        4)
            read -rp "IP address: " hosts_ip
            read -rp "Hostname(s) (space-separated): " hosts_name
            read -rp "Comment [optional]: " hosts_comment
            local entry="$hosts_ip  $hosts_name"
            [[ -n "$hosts_comment" ]] && entry+="  # $hosts_comment"
            echo "$entry" >> /etc/hosts
            log_success "Added to /etc/hosts: $entry"
            audit "HOSTS_ADD" "$entry"
            ;;
        5)
            read -rp "Hostname or IP to remove from /etc/hosts: " hosts_remove
            if grep -q "$hosts_remove" /etc/hosts; then
                cp /etc/hosts /etc/hosts.bak."$(date +%Y%m%d%H%M%S)"
                sed -i "/$hosts_remove/d" /etc/hosts
                log_success "Entry '$hosts_remove' removed from /etc/hosts. Backup saved."
                audit "HOSTS_REMOVE" "$hosts_remove"
            else
                log_warn "No entry matching '$hosts_remove' found in /etc/hosts."
            fi
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
        echo -e "${CYAN}${BOLD}â•‘    Linux Network Management Tool v1.0        â•‘${RESET}"
        echo -e "${CYAN}${BOLD}â•‘         github.com/ACESVAGE                  â•‘${RESET}"
        echo -e "${CYAN}${BOLD}â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${RESET}"
        echo ""
        echo "  1) Interface overview"
        echo "  2) Interface management (up/down/IP/DHCP)"
        echo "  3) Connectivity tests (ping/traceroute/curl)"
        echo "  4) DNS tools"
        echo "  5) Open ports & active connections"
        echo "  6) Firewall management (ufw/firewalld/iptables)"
        echo "  7) Bandwidth & traffic monitoring"
        echo "  8) Network scanning (LAN/port scan)"
        echo "  9) Hostname & /etc/hosts management"
        echo " 10) View audit log"
        echo " 11) Exit"
        echo ""
        read -rp "Select an option [1-11]: " choice

        case "$choice" in
            1)  interface_overview ;;
            2)  interface_management ;;
            3)  connectivity_tests ;;
            4)  dns_tools ;;
            5)  ports_and_connections ;;
            6)  firewall_management ;;
            7)  bandwidth_monitoring ;;
            8)  network_scanning ;;
            9)  hostname_management ;;
            10)
                log_section "Audit Log â€” $AUDIT_LOG"
                if [[ -f "$AUDIT_LOG" ]]; then
                    tail -50 "$AUDIT_LOG"
                else
                    log_warn "No audit log found yet."
                fi
                ;;
            11) log_info "Exiting. Stay secure! ðŸ›¡ï¸"; exit 0 ;;
            *)  log_error "Invalid option. Choose 1â€“11." ;;
        esac
    done
}

# =============================================================================
# ENTRY POINT
# =============================================================================
check_root
main_menu
