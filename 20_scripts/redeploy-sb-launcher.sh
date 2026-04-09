#!/usr/bin/env bash
#
# Redeploy the SilverBullet vault launcher to freeBox after editing
# 20_scripts/sb-launcher.py.
#
# Run from the Mac. Will scp the new launcher.py to freeBox, then
# sudo-restart the systemd service so the new code takes effect.
#
# You'll be prompted once for your sudo password on freeBox.
#
# This is meant for the iterative dev loop. The first-time install
# (systemd unit + tailscale serve mount) lives in install-sb-launcher.sh
# and only needs to run once.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_FILE="${SCRIPT_DIR}/sb-launcher.py"
REMOTE_PATH="/home/frimann/silverbullet-launcher/launcher.py"

if [[ ! -f "$LOCAL_FILE" ]]; then
    echo "missing: $LOCAL_FILE" >&2
    exit 1
fi

# Quick syntax check before pushing — fail fast if the file is broken
python3 -c "import ast; ast.parse(open('${LOCAL_FILE}').read())"

scp "$LOCAL_FILE" "freebox:${REMOTE_PATH}"

ssh -t freebox 'sudo systemctl restart sb-launcher \
  && sleep 1 \
  && systemctl status sb-launcher --no-pager | head -10'
