#!/usr/bin/env bash
#
# mac-workstation-restart.sh — hard-restart the freeMac always-on workstation:
# kill every tmux session, quit Obsidian, then invoke mac-workstation-up.sh to
# rebuild the steady state (one detached tmux session per vault running
# `claude remote-control --name "fm-<vault>-<MMdd-HHmm>"`, plus one Obsidian
# window per vault).
#
# Use this when something is wedged and you want a guaranteed-clean start.
# For a light "just bring back whatever is missing" pass, run
# mac-workstation-up.sh directly — it's idempotent and leaves running
# sessions alone.
#
# Manual:
#   bash ~/Programming/freeBox/20_scripts/mac-workstation-restart.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UP_SCRIPT="$SCRIPT_DIR/mac-workstation-up.sh"

log() {
  printf '[mac-workstation-restart] %s\n' "$1"
}

if [[ ! -x "$UP_SCRIPT" && ! -f "$UP_SCRIPT" ]]; then
  log "ERROR: $UP_SCRIPT not found"
  exit 1
fi

# --- 1. Kill all tmux sessions -------------------------------------------
if command -v tmux >/dev/null 2>&1 && tmux ls >/dev/null 2>&1; then
  log "killing tmux server"
  tmux kill-server 2>/dev/null || true
else
  log "no tmux server running, skipping"
fi

# --- 2. Quit Obsidian ----------------------------------------------------
if pgrep -x Obsidian >/dev/null 2>&1; then
  log "quitting Obsidian"
  osascript -e 'quit app "Obsidian"' 2>/dev/null || true
  # Give Obsidian a moment to shut down before we re-open it.
  for _ in 1 2 3 4 5; do
    pgrep -x Obsidian >/dev/null 2>&1 || break
    sleep 1
  done
else
  log "Obsidian not running, skipping"
fi

# --- 3. Bring everything back up -----------------------------------------
log "invoking $UP_SCRIPT"
bash "$UP_SCRIPT"

log "done"
