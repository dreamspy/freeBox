#!/usr/bin/env bash
#
# mac-obsidian-up.sh — open Obsidian for every vault in ~/Vaults/
#
# Idempotent. If a vault is already open, Obsidian focuses the existing window.
# Safe to call from a LaunchAgent at login.
#
# Manual:
#   bash ~/Vaults/freeBox/20_scripts/mac-obsidian-up.sh
#
# Automatic on login:
#   ~/Library/LaunchAgents/com.freemac.obsidian.plist
#
# Environment overrides:
#   VAULTS_DIR   default: $HOME/Vaults
#
set -euo pipefail

VAULTS_DIR="${VAULTS_DIR:-$HOME/Vaults}"

log() {
  printf '[mac-obsidian-up] %s\n' "$1"
}

if [[ ! -d "$VAULTS_DIR" ]]; then
  log "ERROR: vaults directory $VAULTS_DIR does not exist"
  exit 1
fi

shopt -s nullglob
vault_dirs=()
for vault_dir in "$VAULTS_DIR"/*/; do
  vault_dirs+=("${vault_dir%/}")
done

if [[ "${#vault_dirs[@]}" -eq 0 ]]; then
  log "WARNING: no vault subdirectories found under $VAULTS_DIR"
  exit 0
fi

log "opening Obsidian for ${#vault_dirs[@]} vaults"

for vault_dir in "${vault_dirs[@]}"; do
  name="$(basename "$vault_dir")"
  log "open obsidian://open?vault=$name"
  /usr/bin/open "obsidian://open?vault=${name}" || log "WARNING: open failed for vault $name"
  sleep 1
done

log "done"
