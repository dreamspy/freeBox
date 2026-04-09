#!/usr/bin/env bash
#
# mac-workstation-up.sh — bring the freeMac always-on workstation back to its
# steady state: one detached tmux session per vault running:
#
#   claude remote-control --name "freemac-<sanitized-vault-name>"
#
# plus one Obsidian window open per vault.
#
# Idempotent. Safe to re-run. Safe to call from a LaunchAgent at login.
#
# Manual:
#   bash ~/Vaults/freeBox/20_scripts/mac-workstation-up.sh
#
# Automatic on login:
#   ~/Library/LaunchAgents/com.freebox.mac-workstation.plist
#   (see 10_docs/mac-workstation.md §4 for the plist contents and how to load it)
#
# Environment overrides:
#   VAULTS_DIR   default: $HOME/Vaults
#
set -euo pipefail

VAULTS_DIR="${VAULTS_DIR:-$HOME/Vaults}"

# LaunchAgents do not source shell rc files. Build a PATH that contains the
# usual locations for Homebrew (Apple Silicon and Intel) plus the Claude
# install dir, so the script works whether invoked from a terminal or launchd.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$HOME/.claude/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

log() {
  printf '[mac-workstation-up] %s\n' "$1"
}

# Sanitize a vault name into something safe for tmux session names and the
# Claude Code Remote Control --name flag: transliterate Unicode to ASCII
# (Björn -> Bjorn) using iconv, lowercase, collapse non-alphanumeric runs
# to a single underscore, strip leading/trailing underscores.
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

# --- 1. Sanity checks ----------------------------------------------------
if ! command -v tmux >/dev/null 2>&1; then
  log "ERROR: tmux not found in PATH. Install with: brew install tmux"
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  log "ERROR: claude not found in PATH. Install with: curl -fsSL https://claude.ai/install.sh | bash"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  log "ERROR: python3 not found; needed to update ~/.claude.json trust entries."
  exit 1
fi

if [[ ! -d "$VAULTS_DIR" ]]; then
  log "ERROR: vaults directory $VAULTS_DIR does not exist"
  exit 1
fi

# --- 2. Collect vault dirs ------------------------------------------------
log "scanning $VAULTS_DIR for vaults"

shopt -s nullglob
vault_dirs=()
for vault_dir in "$VAULTS_DIR"/*/; do
  vault_dirs+=("${vault_dir%/}")
done

if [[ "${#vault_dirs[@]}" -eq 0 ]]; then
  log "WARNING: no vault subdirectories found under $VAULTS_DIR"
  log "done"
  exit 0
fi

# --- 3. Pre-trust each vault dir in ~/.claude.json ------------------------
# `claude remote-control` refuses to start in an untrusted workspace and exits
# immediately, which kills the wrapping tmux session. Pre-populate the trust
# state in ~/.claude.json so each vault is already trusted before we launch.
log "pre-trusting ${#vault_dirs[@]} vault dirs in ~/.claude.json"
python3 - "${vault_dirs[@]}" <<'PYEOF'
import json, os, sys
p = os.path.expanduser("~/.claude.json")
try:
    with open(p) as f:
        d = json.load(f)
except FileNotFoundError:
    d = {}
projects = d.setdefault("projects", {})
added = 0
for key in sys.argv[1:]:
    entry = projects.setdefault(key, {})
    if not entry.get("hasTrustDialogAccepted"):
        entry["hasTrustDialogAccepted"] = True
        added += 1
tmp = p + ".tmp"
with open(tmp, "w") as f:
    json.dump(d, f, indent=2)
os.replace(tmp, p)
print(f"[mac-workstation-up]   trust entries added: {added}/{len(sys.argv)-1}")
PYEOF

# --- 4. Start one tmux session per vault ----------------------------------
vault_count=0
new_sessions=0

for vault_dir in "${vault_dirs[@]}"; do
  vault_count=$((vault_count + 1))
  raw_name="$(basename "$vault_dir")"
  safe_name="$(sanitize "$raw_name")"

  if [[ -z "$safe_name" ]]; then
    log "WARNING: vault '$raw_name' sanitizes to empty string, skipping"
    continue
  fi

  session="vault-${safe_name}"
  remote_name="freemac-${safe_name}"

  if tmux has-session -t "$session" 2>/dev/null; then
    log "session $session already exists, skipping"
    continue
  fi

  log "starting tmux session $session in $vault_dir (remote: $remote_name)"
  tmux new-session -d -s "$session" -c "$vault_dir" \
    "claude remote-control --spawn=same-dir --name \"$remote_name\""
  new_sessions=$((new_sessions + 1))
done

log "tmux sessions: $vault_count vaults total, $new_sessions newly started"
tmux ls 2>/dev/null || true

# --- 5. Open Obsidian on each vault --------------------------------------
# We always fire the obsidian:// URL handler. If a vault is already open,
# Obsidian focuses the existing window instead of opening a duplicate.
log "opening Obsidian windows for each vault"

for vault_dir in "${vault_dirs[@]}"; do
  name="$(basename "$vault_dir")"
  log "open obsidian://open?vault=$name"
  /usr/bin/open "obsidian://open?vault=${name}" || log "WARNING: open failed for vault $name"
  sleep 1
done

log "done"
