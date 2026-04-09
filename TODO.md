# freeBox setup TODO

Working checklist for getting freeBox into a fully usable state. Detailed steps live in [`10_docs/setup.md`](10_docs/setup.md).

## Already done

- [x] Provision Linode VPS (Ubuntu 24.04 LTS)
- [x] SSH access via `~/.ssh/config` alias `freebox`
- [x] Install Tailscale and join the tailnet (Tailscale IP in `SECRETS.md`)
- [x] Clean up `~/.ssh/config` (route `freebox` via Tailscale by default, public IP as commented fallback)

## Server provisioning

- [ ] Reboot freeBox if a kernel update is pending (`/var/run/reboot-required`)
- [x] `sudo apt update && sudo apt upgrade -y`
- [x] Install base tools: `sudo apt install -y tmux git curl wget unzip ripgrep fd-find zsh htop build-essential ufw`
- [x] `sudo timedatectl set-timezone Atlantic/Reykjavik`
- [ ] Do this regularely, by running bootstrap.sh

> Shortcut: `scp 20_scripts/bootstrap.sh freebox:~/ && ssh freebox 'sudo bash ~/bootstrap.sh'` covers the four items above plus ufw.

## Claude Code

- [x] Install Claude Code: `curl -fsSL https://claude.ai/install.sh | bash`
- [x] Verify: `claude --version`
- [x] Authenticate (first `claude` run prompts a browser login flow)
- [x] Start persistent session: `tmux new -s claude`, then `claude` inside tmux
- [x] Test Claude Remote Control from iPhone (`/remote-control` from inside Claude)

## Workspace

- [x] `mkdir -p ~/work` for repos and terminal projects

## Network and security

- [x] Enable firewall: `sudo ufw allow OpenSSH && sudo ufw enable` (allow before enable — order matters)
- [x] Verify: `sudo ufw status verbose`
- [x] **Optional, defer until both fallbacks verified:** harden `/etc/ssh/sshd_config` (`PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes`), then `sudo systemctl restart ssh`

## Final check

- [x] Run `bash 20_scripts/check-health.sh` on freeBox and confirm: SSH active, ufw active, Tailscale connected, Claude installed, tmux session present
- [ ] From a *different* machine, confirm `ssh freebox` still works (Tailscale path) and `ssh <your-user>@<public-ip>` still works (direct path) — i.e. both fallbacks are healthy before any hardening

## Vaults on freeBox (Syncthing + per-vault Claude sessions)

> **Decided 2026-04-09 — reverses the 2026-04-08 "vaults off freeBox" deferral.** Vaults live on freeBox at `~/Vaults/<vault>/` and sync to the Mac (and any other peer) via **Syncthing** over Tailscale. Per-vault Claude Code Remote Control sessions are started by [`20_scripts/freebox-vaults-up.sh`](20_scripts/freebox-vaults-up.sh). See [`10_docs/obsidian-sync.md`](10_docs/obsidian-sync.md) for the decision block and [`10_docs/freebox-services.md`](10_docs/freebox-services.md) for the running services.

- [x] Decide on a sync strategy for Obsidian vaults on freeBox — Syncthing
- [x] Copy all important vaults onto freeBox under `~/Vaults/<vault>/` — done via Syncthing peering with the Mac
- [x] For each vault, start a dedicated Claude session via `freebox-vaults-up.sh` (one detached tmux session per vault running `claude remote-control --name "freebox-<sanitized-vault>"`)
- [x] Document the per-vault session naming convention — see the script header and `10_docs/freebox-services.md`
- [x] Enable lingering so the systemd user unit starts the sessions at boot: `sudo loginctl enable-linger frimann` (one-time, requires sudo)
- [x] Verify the unit auto-starts after a real reboot — confirmed 2026-04-09: all vault tmux sessions came back up automatically
- [ ] Add `.stignore` `(?d)` prefixes for volatile patterns (`.DS_Store`, `.obsidian/workspace*`, `.obsidian/cache`, etc.) so Syncthing can delete dirs containing those on a peer — see `10_docs/obsidian-sync.md` for the gotcha

## Mac always-on workstation (active experiment, 2026-04-09)

> Testing a MacBook Pro (M1, fresh macOS) as a 24/7 workstation for Claude + Obsidian. freeBox is parked while this runs. Full runbook in [`10_docs/mac-workstation.md`](10_docs/mac-workstation.md). Helper script: [`20_scripts/mac-workstation-up.sh`](20_scripts/mac-workstation-up.sh).

### Phase 1 — Always-on power management

- [ ] Apply `pmset` settings (`sleep 0`, `disksleep 0`, `womp 1`, `autorestart 1`, etc. — see runbook §1.1)
- [ ] Verify with `pmset -g`
- [ ] Plug Mac in permanently; trust Optimized Battery Charging
- [ ] (Later, when going lid-closed) install Amphetamine and enable its lid-closed trigger
- [ ] Install Tailscale (`brew install --cask tailscale`), sign in to the same tailnet as freeBox + iPhone
- [ ] Verify Mac's tailnet IP is reachable from the iPhone

### Phase 2 — Vaults via Obsidian Sync

- [ ] `brew install --cask obsidian`
- [ ] `mkdir -p ~/vaults`
- [ ] Sign in to Obsidian Sync inside Obsidian
- [ ] For each remote vault: pull to `~/vaults/<vault-name>` via the "Show vaults stored in Obsidian Sync" picker
- [ ] Verify bidirectional sync with the iPhone for one vault
- [ ] `ls ~/vaults && du -sh ~/vaults` — confirm all vaults present and total size sane

### Phase 3 — Claude Code + per-vault sessions

- [ ] `curl -fsSL https://claude.ai/install.sh | bash`
- [ ] `brew install tmux`
- [ ] First interactive `claude` run to complete the browser auth flow (must happen before the LaunchAgent fires)
- [ ] Clone this repo to `~/Programming/freeBox`
- [ ] Run `bash ~/Programming/freeBox/20_scripts/mac-workstation-up.sh` and verify `tmux ls` shows one session per vault and Obsidian opened a window per vault
- [ ] Pair iPhone Claude Code Remote Control with at least one session via `/remote-control`

### Phase 4 — Auto-start after login

- [ ] Install the LaunchAgent at `~/Library/LaunchAgents/com.freebox.mac-workstation.plist` (heredoc command in runbook §4.1)
- [ ] `launchctl load` it
- [ ] Test by killing `tmux` and Obsidian, then unloading + reloading the agent (see runbook §4.2)
- [ ] Real reboot test: `sudo reboot`, type FileVault password, confirm sessions and Obsidian windows come back automatically

### Phase 5 — Decide whether this is permanent

- [ ] Use the setup for a few weeks of normal work
- [ ] Decide: keep Mac as primary, go back to freeBox, or hybrid
- [ ] Update `10_docs/obsidian-sync.md` and the freeBox sections of this TODO with the result
- [ ] (If keeping Mac) revisit freeBox's role — backup workstation, build box, retire?

### Optional hardening

- [ ] Put the Mac on a small UPS to eliminate brief power outages as a reboot trigger (the only common cause of "Mac unreachable until I walk to it" with FileVault on)

## Later / nice to have

- [ ] Decide whether to enable Tailscale SSH (`sudo tailscale up --ssh`) — eliminates manual SSH key management for the private path
- [ ] Disable Tailscale key expiry on this machine in the [admin console](https://login.tailscale.com/admin/machines) so it doesn't drop off the tailnet after 180 days
- [ ] Set up an auto-reattach helper or systemd user unit for the `claude` tmux session, so it survives reboots
