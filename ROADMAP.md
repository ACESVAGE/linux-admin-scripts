# ðŸ›¡ï¸ Linux Admin & Cybersecurity Bash Scripts â€” Learning Roadmap

> Scripts are written and pushed daily. Each one builds on the last.
> Repository: [ACESVAGE/linux-admin-scripts](https://github.com/ACESVAGE/linux-admin-scripts)

---

## ðŸ“ Phase 1 â€” Linux System Administration (Foundation)
*Master the Linux environment before moving into security.*

| # | Script | Folder | Concepts Covered | Status |
|---|--------|--------|-----------------|--------|
| 1 | `user_management.sh` | `admin/user-management/` | useradd, usermod, userdel, chage, groups, sudo | âœ… Done |
| 2 | `disk_management.sh` | `admin/disk-management/` | df, du, lsblk, fdisk, mount, quota, cleanup | â³ Next |
| 3 | `network_diagnostics.sh` | `admin/network/` | ip, ifconfig, ping, traceroute, netstat, ss, curl | â¬œ |
| 4 | `backup_restore.sh` | `admin/backup/` | tar, rsync, cron scheduling, incremental backups | â¬œ |
| 5 | `system_monitor.sh` | `admin/monitoring/` | top, htop, vmstat, iostat, uptime, free, alerts | â¬œ |
| 6 | `log_manager.sh` | `admin/monitoring/` | journalctl, logrotate, grep patterns, log archiving | â¬œ |
| 7 | `service_manager.sh` | `admin/monitoring/` | systemctl, service health checks, auto-restart | â¬œ |
| 8 | `firewall_manager.sh` | `admin/network/` | ufw, iptables rules, port allow/deny, status report | â¬œ |

---

## ðŸ“ Phase 2 â€” Cybersecurity Fundamentals
*Learn reconnaissance, scanning, and system hardening.*

| # | Script | Folder | Concepts Covered | Status |
|---|--------|--------|-----------------|--------|
| 9 | `host_discovery.sh` | `cybersecurity/network-scanning/` | ping sweep, ARP scan, nmap basics | â¬œ |
| 10 | `port_scanner.sh` | `cybersecurity/network-scanning/` | nmap, TCP/UDP scanning, banner grabbing | â¬œ |
| 11 | `whois_recon.sh` | `cybersecurity/recon/` | whois, dig, nslookup, OSINT from domain | â¬œ |
| 12 | `subdomain_enum.sh` | `cybersecurity/recon/` | DNS brute-forcing, subfinder concepts | â¬œ |
| 13 | `system_hardening.sh` | `cybersecurity/hardening/` | SSH config, disable root login, fail2ban setup | â¬œ |
| 14 | `password_auditor.sh` | `cybersecurity/hardening/` | Weak password detection, policy enforcement | â¬œ |
| 15 | `open_ports_audit.sh` | `cybersecurity/hardening/` | Find unexpected open ports, service mapping | â¬œ |
| 16 | `ssh_hardening.sh` | `cybersecurity/hardening/` | SSH key setup, disable passwords, port change | â¬œ |

---

## ðŸ“ Phase 3 â€” Threat Detection & Log Analysis
*Learn to detect attacks and suspicious activity.*

| # | Script | Folder | Concepts Covered | Status |
|---|--------|--------|-----------------|--------|
| 17 | `failed_login_detector.sh` | `cybersecurity/log-analysis/` | auth.log parsing, brute-force detection | â¬œ |
| 18 | `intrusion_detector.sh` | `cybersecurity/log-analysis/` | anomaly detection, pattern matching | â¬œ |
| 19 | `file_integrity_checker.sh` | `cybersecurity/log-analysis/` | md5sum/sha256, baseline comparison | â¬œ |
| 20 | `rootkit_scanner.sh` | `cybersecurity/log-analysis/` | rkhunter concepts, suspicious process detection | â¬œ |
| 21 | `network_traffic_monitor.sh` | `cybersecurity/log-analysis/` | tcpdump, traffic analysis, connection tracking | â¬œ |

---

## ðŸ“ Phase 4 â€” Offensive Security & CTF Tools
*Ethical hacking tools for authorized testing and CTF challenges.*

| # | Script | Folder | Concepts Covered | Status |
|---|--------|--------|-----------------|--------|
| 22 | `web_recon.sh` | `cybersecurity/recon/` | curl, headers, robots.txt, dirbusting | â¬œ |
| 23 | `hash_cracker_helper.sh` | `cybersecurity/ctf/` | hashid, john, hashcat wrapper | â¬œ |
| 24 | `reverse_shell_cheatsheet.sh` | `cybersecurity/ctf/` | Common reverse shell one-liners (reference) | â¬œ |
| 25 | `vuln_scanner.sh` | `cybersecurity/network-scanning/` | nmap scripting engine (NSE), CVE lookups | â¬œ |
| 26 | `ctf_toolkit.sh` | `cybersecurity/ctf/` | Base64, rot13, hex decode, steganography hints | â¬œ |

---

## ðŸ“ Phase 5 â€” Advanced Automation & DevSecOps
*Tie everything together with automation and CI/CD security.*

| # | Script | Folder | Concepts Covered | Status |
|---|--------|--------|-----------------|--------|
| 27 | `cron_job_manager.sh` | `admin/backup/` | crontab management, scheduling, validation | â¬œ |
| 28 | `ssl_cert_checker.sh` | `admin/network/` | openssl, cert expiry alerts, chain validation | â¬œ |
| 29 | `automated_report.sh` | `admin/monitoring/` | Full system security report, email/slack alerts | â¬œ |
| 30 | `setup_new_server.sh` | `admin/` | Full server provisioning from scratch | â¬œ |

---

## ðŸ—“ï¸ Daily Session Format

Each session we will:
1. **Review** the previous script briefly
2. **Write** the next script with full explanations
3. **Commit** it to the correct folder in GitHub
4. **Update** this roadmap (mark âœ…)

---

## ðŸ”‘ Legend
| Symbol | Meaning |
|--------|---------|
| âœ… Done | Script written, committed, and reviewed |
| â³ Next | This is the next script to be written |
| â¬œ Queued | Scheduled for a future session |

---

*Last updated: 2026-10-24 â€¢ Roadmap version 1.0*
