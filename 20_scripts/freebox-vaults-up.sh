#!/usr/bin/env bash
#
# freebox-vaults-up.sh — bring up one detached tmux session per vault under
# ~/vaults on the freeBox server, each running:
#
#   claude remote-control --name "fb-<sanitized-vault-name>-<MMdd-HHmm>"
#
# Idempotent. Safe to re-run: existing sessions are left alone.
#
# Run on freeBox (not on the Mac):
#   ssh freebox 'bash ~/freebox-vaults-up.sh'
# or after copying into the repo on the server:
#   bash ~/Programming/freeBox/20_scripts/freebox-vaults-up.sh
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

if ! command -v python3 >/dev/null 2>&1; then
  log "ERROR: python3 not found; needed to update ~/.claude.json trust entries."
  exit 1
fi

if [[ ! -d "$VAULTS_DIR" ]]; then
  log "ERROR: vaults directory $VAULTS_DIR does not exist"
  exit 1
fi

# --- 2. Collect vault dirs ----------------------------------------------
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

# --- 3. Pre-trust each vault dir in ~/.claude.json ----------------------
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
print(f"[freebox-vaults-up]   trust entries added: {added}/{len(sys.argv)-1}")
PYEOF

# --- 4. Start one tmux session per vault --------------------------------
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
  remote_name="fb-${safe_name}-$(date +%m%d-%H%M)"

  if tmux has-session -t "$session" 2>/dev/null; then
    log "session $session already exists, skipping"
    continue
  fi

  log "starting tmux session $session in $vault_dir (remote: $remote_name)"
  # Wrap claude in a respawn loop: if it exits (registration race at boot,
  # network blip, crash), the loop brings it back. The tmux session then
  # outlives any single claude process.
  tmux new-session -d -s "$session" -c "$vault_dir" \
    "while true; do claude remote-control --spawn=same-dir --name \"$remote_name\"; sleep 5; done"
  new_sessions=$((new_sessions + 1))
done

log "tmux sessions: $vault_count vaults total, $new_sessions newly started"

# --- 5. Clean up orphaned sessions for deleted vaults ---------------------
# Build a set of expected session names from the vault dirs we just processed,
# then kill any vault-* tmux session that isn't in the set.
declare -A expected_sessions
for vault_dir in "${vault_dirs[@]}"; do
  safe="$(sanitize "$(basename "$vault_dir")")"
  [[ -n "$safe" ]] && expected_sessions["vault-${safe}"]=1
done

killed=0
while IFS=: read -r sess _rest; do
  # Only consider sessions with the vault- prefix
  if [[ "$sess" == vault-* ]] && [[ -z "${expected_sessions[$sess]+x}" ]]; then
    log "killing orphaned session $sess (vault dir no longer exists)"
    tmux kill-session -t "$sess"
    killed=$((killed + 1))
  fi
done < <(tmux ls -F '#{session_name}:' 2>/dev/null || true)

if [[ "$killed" -gt 0 ]]; then
  log "cleaned up $killed orphaned session(s)"
fi

tmux ls 2>/dev/null || true

log "done"
