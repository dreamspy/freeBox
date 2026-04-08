# freeBox setup TODO

Working checklist for getting freeBox into a fully usable state. Detailed steps live in [`10_docs/setup.md`](10_docs/setup.md).

## Already done

- [x] Provision Linode VPS (Ubuntu 24.04 LTS)
- [x] SSH access via `~/.ssh/config` alias `freeBox`
- [x] Install Tailscale and join the tailnet (Tailscale IP in `SECRETS.md`)
- [x] Clean up `~/.ssh/config` (route `freeBox` via Tailscale by default, public IP as commented fallback)

## Server provisioning

- [ ] Reboot freeBox if a kernel update is pending (`/var/run/reboot-required`)
- [x] `sudo apt update && sudo apt upgrade -y`
- [x] Install base tools: `sudo apt install -y tmux git curl wget unzip ripgrep fd-find zsh htop build-essential ufw`
- [x] `sudo timedatectl set-timezone Atlantic/Reykjavik`

> Shortcut: `scp 20_scripts/bootstrap.sh freeBox:~/ && ssh freeBox 'sudo bash ~/bootstrap.sh'` covers the four items above plus ufw.

## Claude Code

- [x] Install Claude Code: `curl -fsSL https://claude.ai/install.sh | bash`
- [x] Verify: `claude --version`
- [x] Authenticate (first `claude` run prompts a browser login flow)
- [x] Start persistent session: `tmux new -s claude`, then `claude` inside tmux
- [ ] Test Claude Remote Control from iPhone (`/remote-control` from inside Claude)

## Workspace

- [ ] `mkdir -p ~/work` for repos and terminal projects

## Network and security

- [x] Enable firewall: `sudo ufw allow OpenSSH && sudo ufw enable` (allow before enable — order matters)
- [ ] Verify: `sudo ufw status verbose`
- [x] **Optional, defer until both fallbacks verified:** harden `/etc/ssh/sshd_config` (`PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes`), then `sudo systemctl restart ssh`

## Final check

- [ ] Run `bash 20_scripts/check-health.sh` on freeBox and confirm: SSH active, ufw active, Tailscale connected, Claude installed, tmux session present
- [ ] From a *different* machine, confirm `ssh freeBox` still works (Tailscale path) and `ssh frimann@<public-ip>` still works (direct path) — i.e. both fallbacks are healthy before any hardening

## Obsidian on the server

- [ ] Decide on a sync strategy for Obsidian vaults on freeBox. Options to evaluate:
  - **Obsidian Sync** — official, end-to-end encrypted, costs money, but works on a headless server only via the CLI / file watcher trick (no GUI). Needs a workaround.
  - **Git** — every vault is a git repo, push/pull on demand or via cron. Free, simple, but no real-time sync and merge conflicts on binary attachments are painful.
  - **Syncthing** — peer-to-peer file sync between Mac/iPhone/freeBox. Free, runs as a daemon, no central server required. Good fit for a headless box.
  - **rsync over Tailscale** — manual or scheduled. Simplest, least magic, no real-time.
- [ ] Pick one approach and document the decision in `10_docs/setup.md` (or a new `10_docs/obsidian.md` if it grows)
- [ ] Copy all important vaults onto freeBox under a known location (e.g. `~/vaults/<vault-name>/`)
- [ ] For each vault, start a dedicated Claude session inside its own tmux window:
  - `tmux new -s vault-<name>` then `cd ~/vaults/<name> && claude`
  - One session per vault keeps context, history, and Remote Control flows isolated
- [ ] Document the per-vault session naming convention so reattaching is predictable

## Later / nice to have

- [ ] Decide whether to enable Tailscale SSH (`sudo tailscale up --ssh`) — eliminates manual SSH key management for the private path
- [ ] Disable Tailscale key expiry on this machine in the [admin console](https://login.tailscale.com/admin/machines) so it doesn't drop off the tailnet after 180 days
- [ ] Set up an auto-reattach helper or systemd user unit for the `claude` tmux session, so it survives reboots
