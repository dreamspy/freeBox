#!/usr/bin/env bash
#
# mac-tmux-ensure.sh — watchdog variant of mac-workstation-up.sh that only
# restarts missing vault-* tmux sessions (no Obsidian, no trust mutation).
#
# Safe to run on a short LaunchAgent interval (StartInterval=60).
#
# Environment overrides:
#   VAULTS_DIR   default: $HOME/Vaults
#
set -euo pipefail

VAULTS_DIR="${VAULTS_DIR:-$HOME/Vaults}"

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

  remote_name="fm-${safe_name}-$(date +%m%d-%H%M)"
  log "restarting missing session $session in $vault_dir (remote: $remote_name)"
  tmux new-session -d -s "$session" -c "$vault_dir" \
    "claude remote-control --spawn=same-dir --name \"$remote_name\""
  restarted=$((restarted + 1))
done

[[ "$restarted" -gt 0 ]] && log "restarted $restarted session(s)"
exit 0
