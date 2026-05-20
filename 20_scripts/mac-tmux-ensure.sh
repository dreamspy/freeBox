#!/usr/bin/env bash
#
# mac-tmux-ensure.sh — watchdog variant of mac-workstation-up.sh that only
# restarts missing vault-* tmux sessions (no Obsidian, no trust mutation).
#
# Safe to run on a short LaunchAgent interval (StartInterval=60).
#
# Each restarted tmux session pipes claude's stdout/stderr + exit code to a
# per-vault log under $LOG_DIR so we can investigate respawn churn.
#
# Environment overrides:
#   VAULTS_DIR   default: $HOME/Vaults
#   LOG_DIR      default: $HOME/Library/Logs/freemac-vaults
#
set -euo pipefail

VAULTS_DIR="${VAULTS_DIR:-$HOME/Vaults}"
LOG_DIR="${LOG_DIR:-$HOME/Library/Logs/freemac-vaults}"
mkdir -p "$LOG_DIR"

# LaunchAgents do not source shell rc files.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.claude/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

log() {
  printf '[mac-tmux-ensure] %s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1"
}

sanitize() {
  local s="$1"
  if command -v iconv >/dev/null 2>&1; then
    local t
    if t="$(printf '%s' "$s" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null)"; then
      s="$t"
    fi
  fi
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
  s="${s//[^a-z0-9]/_}"
  while [[ "$s" == *__* ]]; do s="${s//__/_}"; done
  s="${s#_}"
  s="${s%_}"
  printf '%s' "$s"
}

command -v tmux   >/dev/null 2>&1 || { log "ERROR: tmux not on PATH"; exit 1; }
command -v claude >/dev/null 2>&1 || { log "ERROR: claude not on PATH"; exit 1; }
[[ -d "$VAULTS_DIR" ]] || { log "ERROR: $VAULTS_DIR missing"; exit 1; }

shopt -s nullglob
restarted=0
for vault_dir in "$VAULTS_DIR"/*/; do
  vault_dir="${vault_dir%/}"
  safe_name="$(sanitize "$(basename "$vault_dir")")"
  [[ -z "$safe_name" ]] && continue

  session="vault-${safe_name}"
  if tmux has-session -t "$session" 2>/dev/null; then
    continue
  fi

  remote_name="fm-$(date +%m%d-%H%M)-${safe_name}"
  vault_log="$LOG_DIR/${safe_name}.log"
  log "restarting missing session $session in $vault_dir (remote: $remote_name, log: $vault_log)"
  printf '[%s] watchdog restarting (prior tmux gone) name=%s\n' \
    "$(date -Iseconds)" "$remote_name" >> "$vault_log"
  tmux new-session -d -s "$session" -c "$vault_dir" \
    "printf '[%s] start name=%s pid=%s\n' \"\$(date -Iseconds)\" '$remote_name' \"\$\$\" >> '$vault_log'; \
     claude remote-control --spawn=same-dir --name \"$remote_name\" >> '$vault_log' 2>&1; \
     printf '[%s] exit name=%s code=%d (tmux ending)\n' \"\$(date -Iseconds)\" '$remote_name' \$? >> '$vault_log'"
  restarted=$((restarted + 1))
done

[[ "$restarted" -gt 0 ]] && log "restarted $restarted session(s)"
exit 0
