#!/usr/bin/env bash
#
# Install the SilverBullet vault launcher on freeBox.
#
# Run this from the Mac (after `20_scripts/sb-launcher.py` has already been
# copied to freeBox at /home/frimann/silverbullet-launcher/launcher.py — the
# main session does this with `scp` before running this script).
#
# What it does on freeBox:
#   1. Writes /etc/systemd/system/sb-launcher.service (sudo)
#   2. Reloads systemd, enables + starts the launcher service (sudo)
#   3. Adds /launcher as a second mount on the existing tailscale serve
#      config (no sudo because the user is the tailscale operator)
#   4. Prints status + the new serve config so you can verify
#
# Reversible. To uninstall later:
#   ssh freebox 'sudo systemctl disable --now sb-launcher \
#       && sudo rm /etc/systemd/system/sb-launcher.service \
#       && sudo systemctl daemon-reload \
#       && tailscale serve --https=443 --set-path=/launcher off'
#
# You will be prompted once for your sudo password on freeBox.

set -euo pipefail

ssh -t freebox 'sudo tee /etc/systemd/system/sb-launcher.service > /dev/null << "EOF"
[Unit]
Description=SilverBullet vault launcher (freeBox)
After=network.target docker.service

[Service]
Type=simple
User=frimann
Group=frimann
SupplementaryGroups=docker
ExecStart=/usr/bin/python3 /home/frimann/silverbullet-launcher/launcher.py
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload \
  && sudo systemctl enable --now sb-launcher \
  && sleep 2 \
  && systemctl status sb-launcher --no-pager | head -15 \
  && tailscale serve --bg --https=443 --set-path=/launcher http://127.0.0.1:3001 \
  && tailscale serve status'
