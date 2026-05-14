#!/usr/bin/env bash
#
# mac-creds-kick.sh — triggered by com.freebox.mac-creds-watch LaunchAgent
# when ~/.claude/.credentials.json changes. Kills running `claude` processes
# so the tmux sessions exit, then re-invokes mac-tmux-ensure.sh to recreate
# them with the fresh credentials.
#
# Unlike mac-workstation-up.sh, this does NOT touch Obsidian, so a routine
# credentials refresh won't shuffle your Obsidian windows.
#
set -euo pipefail

# LaunchAgents do not source shell rc files.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.claude/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

log() {
  printf '[mac-creds-kick] %s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENSURE_SCRIPT="$SCRIPT_DIR/mac-tmux-ensure.sh"

log "credentials change detected, kicking claude"

if pkill -x claude 2>/dev/null; then
  log "sent SIGTERM to claude processes"
else
  log "no claude processes were running"
fi

# Give tmux a moment to tear down the now-empty sessions before we
# recreate them.
sleep 2

if [[ -x "$ENSURE_SCRIPT" ]]; then
  log "invoking $ENSURE_SCRIPT"
  bash "$ENSURE_SCRIPT"
else
  log "ERROR: $ENSURE_SCRIPT not found or not executable"
  exit 1
fi

log "done"
