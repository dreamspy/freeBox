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

# Synchronously tear down all vault-* tmux sessions so mac-tmux-ensure
# can recreate every one. We do this explicitly rather than waiting for
# tmux sessions to exit naturally after claude dies: that cascade can
# take a variable amount of time and races mac-tmux-ensure.sh, leaving
# some sessions still half-alive when the recreate pass runs.
killed=0
if command -v tmux >/dev/null 2>&1 && tmux ls >/dev/null 2>&1; then
  while IFS= read -r session; do
    [[ -z "$session" ]] && continue
    if [[ "$session" == vault-* ]]; then
      tmux kill-session -t "$session" 2>/dev/null && killed=$((killed + 1)) || true
    fi
  done < <(tmux ls -F '#{session_name}' 2>/dev/null)
fi
log "killed $killed vault-* tmux session(s)"

if [[ -x "$ENSURE_SCRIPT" ]]; then
  log "invoking $ENSURE_SCRIPT"
  bash "$ENSURE_SCRIPT"
else
  log "ERROR: $ENSURE_SCRIPT not found or not executable"
  exit 1
fi

log "done"
