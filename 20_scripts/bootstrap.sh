#!/usr/bin/env bash
#
# freeBox bootstrap — first-time provisioning for an Ubuntu 24.04 LTS VPS.
#
# Run with sudo from your normal user account:
#   sudo bash bootstrap.sh
#
# WARNING: this script enables ufw. It allows OpenSSH (port 22) before
# enabling, so a standard SSH session is safe. If you have moved SSH to a
# non-standard port, allow that port BEFORE running this script, or you will
# lock yourself out.
#
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root or with sudo." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

USER_NAME="${SUDO_USER:-${USER:-}}"
if [[ -z "$USER_NAME" || "$USER_NAME" == "root" ]]; then
  echo "Could not determine the normal user. Run this with sudo from your normal user account." >&2
  exit 1
fi

log() {
  printf '\n==> %s\n' "$1"
}

log "Updating packages"
apt update
apt upgrade -y

log "Installing base packages"
apt install -y \
  tmux git curl wget unzip ripgrep fd-find zsh htop build-essential ufw \
  ca-certificates gnupg lsb-release software-properties-common

log "Setting timezone to Atlantic/Reykjavik"
timedatectl set-timezone Atlantic/Reykjavik || true

log "Configuring UFW: allow OpenSSH then enable"
ufw allow OpenSSH || true
ufw --force enable || true

log "Installing Tailscale if missing"
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
else
  echo "Tailscale already installed"
fi

log "Installing Claude Code if missing"
if ! command -v claude >/dev/null 2>&1; then
  if curl -fsSL https://claude.ai/install.sh | bash; then
    echo "Claude installer completed"
  else
    echo "Claude installer failed, trying npm fallback"
    if ! command -v npm >/dev/null 2>&1; then
      echo "npm not found. Install Node.js first and retry." >&2
      exit 1
    fi
    npm install -g @anthropic-ai/claude-code
  fi
else
  echo "Claude already installed"
fi

log "Creating work folder for $USER_NAME"
sudo -u "$USER_NAME" mkdir -p "/home/$USER_NAME/work"

log "Bootstrap complete"
cat <<EOF

Next steps:
  1. sudo tailscale up           # then complete the browser auth
  2. tmux new -s claude          # start a persistent session
  3. claude                      # inside tmux
  4. (optional) sudo tailscale up --ssh
  5. (optional) harden sshd_config — see 10_docs/10_setup.md step 11
EOF
