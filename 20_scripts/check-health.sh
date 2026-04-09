#!/usr/bin/env bash
#
# freeBox health snapshot — quick read of host, network, and services.
# Safe to run as the normal user. No changes are made.
#
set -euo pipefail

# Ensure user-local bins are visible (non-interactive ssh sessions don't load ~/.profile)
export PATH="$HOME/.local/bin:$PATH"

section() {
  printf '\n### %s ###\n' "$1"
}

section "Host"
hostnamectl 2>/dev/null || true

section "Uptime"
uptime

section "Disk"
df -h /

section "Memory"
free -h

section "Top processes by memory"
ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem | head -n 12

section "Network"
ip -brief addr || true

section "SSH service"
if command -v systemctl >/dev/null 2>&1; then
  systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || true
fi

section "Firewall"
if command -v ufw >/dev/null 2>&1; then
  if sudo -n ufw status verbose 2>/dev/null; then
    :
  else
    echo "ufw: needs sudo (run with: sudo $0, or 'ssh -t freeBox sudo ufw status verbose')"
  fi
fi

section "Tailscale"
if command -v tailscale >/dev/null 2>&1; then
  tailscale status || true
  printf '\nTailscale IPs:\n'
  tailscale ip || true
else
  echo "Tailscale not installed"
fi

section "Claude"
if command -v claude >/dev/null 2>&1; then
  which claude
  claude --version || true
else
  echo "Claude not installed"
fi

section "Node / npm"
if command -v node >/dev/null 2>&1; then
  node -v
else
  echo "node not installed"
fi
if command -v npm >/dev/null 2>&1; then
  npm -v
else
  echo "npm not installed"
fi

section "tmux sessions"
if command -v tmux >/dev/null 2>&1; then
  tmux ls 2>/dev/null || echo "No tmux sessions"
else
  echo "tmux not installed"
fi
