#!/usr/bin/env bash
#
# mac-workstation-up.sh — bring the Mac always-on workstation back to its
# steady state: one detached tmux session running `claude` per vault under
# ~/vaults, plus one Obsidian window open per vault.
#
# Idempotent. Safe to re-run. Safe to call from a LaunchAgent at login.
#
# Manual:
#   bash ~/Programming/freeBox/20_scripts/mac-workstation-up.sh
#
# Automatic on login:
#   ~/Library/LaunchAgents/com.freebox.mac-workstation.plist
#   (see 10_docs/mac-workstation.md §4 for the plist contents and how to load it)
#
# Environment overrides:
#   VAULTS_DIR   default: $HOME/vaults
#
set -euo pipefail

VAULTS_DIR="${VAULTS_DIR:-$HOME/vaults}"

# LaunchAgents do not source shell rc files. Build a PATH that contains the
# usual locations for Homebrew (Apple Silicon and Intel) plus the Claude
# install dir, so the script works whether invoked from a terminal or launchd.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.claude/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

log() {
  printf '[mac-workstation-up] %s\n' "$1"
}

# --- 1. Sanity checks ----------------------------------------------------
if ! command -v tmux >/dev/null 2>&1; then
  log "ERROR: tmux not found in PATH. Install with: brew install tmux"
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  log "ERROR: claude not found in PATH. Install with: curl -fsSL https://claude.ai/install.sh | bash"
  exit 1
fi

if [[ ! -d "$VAULTS_DIR" ]]; then
  log "ERROR: vaults directory $VAULTS_DIR does not exist"
  exit 1
fi

# --- 2. Start one tmux session per vault ---------------------------------
log "scanning $VAULTS_DIR for vaults"

shopt -s nullglob
vault_count=0
new_sessions=0

for vault_dir in "$VAULTS_DIR"/*/; do
  vault_count=$((vault_count + 1))
  name="$(basename "$vault_dir")"
  session="vault-${name}"

  if tmux has-session -t "$session" 2>/dev/null; then
    log "session $session already exists, skipping"
    continue
  fi

  log "starting tmux session $session in $vault_dir"
  tmux new-session -d -s "$session" -c "$vault_dir" "claude"
  new_sessions=$((new_sessions + 1))
done

if [[ "$vault_count" -eq 0 ]]; then
  log "WARNING: no vault subdirectories found under $VAULTS_DIR"
fi

log "tmux sessions: $vault_count vaults total, $new_sessions newly started"
tmux ls 2>/dev/null || true

# --- 3. Open Obsidian on each vault --------------------------------------
# We always fire the obsidian:// URL handler. If a vault is already open,
# Obsidian focuses the existing window instead of opening a duplicate.
log "opening Obsidian windows for each vault"

for vault_dir in "$VAULTS_DIR"/*/; do
  name="$(basename "$vault_dir")"
  log "open obsidian://open?vault=$name"
  /usr/bin/open "obsidian://open?vault=${name}" || log "WARNING: open failed for vault $name"
  sleep 1
done

log "done"
