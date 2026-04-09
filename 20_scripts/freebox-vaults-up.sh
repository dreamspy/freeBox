#!/usr/bin/env bash
#
# freebox-vaults-up.sh — bring up one detached tmux session per vault under
# ~/vaults on the freeBox server, each running:
#
#   claude remote-control --name "freebox-<sanitized-vault-name>"
#
# Idempotent. Safe to re-run: existing sessions are left alone.
#
# Run on freeBox (not on the Mac):
#   ssh freebox 'bash ~/freebox-vaults-up.sh'
# or after copying into the repo on the server:
#   bash ~/freeBox/20_scripts/freebox-vaults-up.sh
#
# Environment overrides:
#   VAULTS_DIR   default: $HOME/Vaults
#
set -euo pipefail

VAULTS_DIR="${VAULTS_DIR:-$HOME/Vaults}"

# Non-interactive ssh and systemd units do not source ~/.profile or ~/.bashrc,
# so $HOME/.local/bin (where the Claude installer puts the `claude` symlink) is
# not on PATH by default. Prepend the usual local install dirs so this script
# works regardless of how it's invoked.
export PATH="$HOME/.local/bin:$HOME/.claude/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

log() {
  printf '[freebox-vaults-up] %s\n' "$1"
}

# Sanitize a vault name into something safe for tmux session names and the
# Claude Code Remote Control --name flag: transliterate Unicode to ASCII
# (Björn -> Bjorn) using GNU iconv, lowercase, collapse non-alphanumeric runs
# to a single underscore, strip leading/trailing underscores.
sanitize() {
  local s="$1"
  if command -v iconv >/dev/null 2>&1; then
    local t
    if t="$(printf '%s' "$s" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null)"; then
      s="$t"
    fi
  fi
  s="${s,,}"
  s="${s//[^a-z0-9]/_}"
  while [[ "$s" == *__* ]]; do s="${s//__/_}"; done
  s="${s#_}"
  s="${s%_}"
  printf '%s' "$s"
}

# --- 1. Sanity checks ----------------------------------------------------
if ! command -v tmux >/dev/null 2>&1; then
  log "ERROR: tmux not found in PATH. Install with: sudo apt install -y tmux"
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  log "ERROR: claude not found in PATH. Install per 10_docs/setup.md."
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
  raw_name="$(basename "$vault_dir")"
  safe_name="$(sanitize "$raw_name")"

  if [[ -z "$safe_name" ]]; then
    log "WARNING: vault '$raw_name' sanitizes to empty string, skipping"
    continue
  fi

  session="vault-${safe_name}"
  remote_name="freebox-${safe_name}"

  if tmux has-session -t "$session" 2>/dev/null; then
    log "session $session already exists, skipping"
    continue
  fi

  log "starting tmux session $session in $vault_dir (remote: $remote_name)"
  tmux new-session -d -s "$session" -c "$vault_dir" \
    "claude remote-control --name \"$remote_name\""
  new_sessions=$((new_sessions + 1))
done

if [[ "$vault_count" -eq 0 ]]; then
  log "WARNING: no vault subdirectories found under $VAULTS_DIR"
fi

log "tmux sessions: $vault_count vaults total, $new_sessions newly started"
tmux ls 2>/dev/null || true

log "done"
