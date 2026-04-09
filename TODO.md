# freeBox setup TODO

Working checklist for getting freeBox into a fully usable state. Detailed steps live in [`10_docs/setup.md`](10_docs/setup.md).

## freeBox — open items

- [x] Test what happens when adding a new vault, and document the full process (create folder, set up Obsidian Sync manually, Syncthing pickup, Claude session, SilverBullet access, etc.)
	- [x] Make Vault folder in ~/Vaults
	- [x] Setup obsidian sync
	- [x] Run claude and accept stuff on server, try to auto-accept
	- [x] Test working with the new vault
		- [x] Does the SB PWA work correctly?
		- [x] Do file changes propogate?
- [ ] Run `bootstrap.sh` regularly for package updates: `scp 20_scripts/bootstrap.sh freebox:~/ && ssh freebox 'sudo bash ~/bootstrap.sh'`
- [ ] From a *different* machine, confirm `ssh freebox` still works (Tailscale path) and `ssh <your-user>@<public-ip>` still works (direct path) — i.e. both fallbacks are healthy

## SilverBullet — open items

> Full runbook: [`10_docs/silverbullet.md`](10_docs/silverbullet.md). Service summary: [`10_docs/freebox-services.md`](10_docs/freebox-services.md).

- [x] End-to-end propagation test (iPhone SB edit → freeBox disk → Syncthing → Mac → Obsidian Sync → iPhone Obsidian; and Claude on freeBox edits same files)
- [ ] Decide whether the JWT-secret-per-vault re-login on first visit is annoying enough to warrant a fixed JWT secret env var (so all vaults share auth state)

## freeMac setup (M1 MacBook Pro as 24/7 Claude + Obsidian workstation)

> MacBook Pro (M1) called **freeMac**. Vault sync via **Obsidian Sync** (same as iPhone). Per-vault Claude remote-control sessions in tmux (same pattern as freeBox). Full runbook: [`10_docs/mac-workstation.md`](10_docs/mac-workstation.md). Helper script: [`20_scripts/mac-workstation-up.sh`](20_scripts/mac-workstation-up.sh).
>
> **Claude remote-control naming convention** (consistent across all machines):
> - freeBox sessions: `freebox-<vault-name>` (via `freebox-vaults-up.sh`)
> - freeMac sessions: `freemac-<vault-name>` (via `mac-workstation-up.sh`)
>
> **Sync topology (decided):**
> ```
> freeBox ⇄ Syncthing ⇄ freeMac ⇄ Obsidian Sync ⇄ iPhone
>     ↑        ⇅                     Obsidian Sync ⇄ Main Mac
>     ↑    Syncthing ⇄ Main Mac
> SilverBullet (iPhone PWA)
> ```
> Both Macs run Syncthing (peer mesh with freeBox) + Obsidian Sync.
> freeMac is the always-on bridge; main Mac syncs when awake.

### Phase 0 — Factory reset + macOS 26

- [x] Back up anything needed from the current install (if any)
- [x] Factory reset the M1 MacBook Pro (Erase All Content and Settings, or Recovery Mode reinstall)
- [ ] Install macOS 26 (clean install)
- [x] Complete initial macOS setup (account, language, etc.)
- [ ] Enable FileVault (accept tradeoff: one manual password entry after every reboot)

### Phase 1 — Base setup + power management

- [x] Set macOS hostname to `freeMac` (System Settings → General → Sharing → Local Hostname)
- [x] Apply `pmset` settings (`sleep 0`, `disksleep 0`, `womp 1`, `autorestart 1`, etc. — see runbook §1.1)
- [ ] Verify with `pmset -g`
- [ ] Plug Mac in permanently; trust Optimized Battery Charging
- [ ] Install Homebrew: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
- [ ] Install Tailscale: `brew install --cask tailscale`
- [ ] Sign into the tailnet (same account as freeBox + iPhone), rename to `freemac` in the [admin console](https://login.tailscale.com/admin/machines)
- [ ] Verify freeMac's tailnet IP is reachable from the iPhone and from this Mac
- [ ] (Later, when going lid-closed) install Amphetamine and enable its lid-closed trigger

### Phase 2 — Vaults via Obsidian Sync

- [ ] `brew install --cask obsidian`
- [ ] `mkdir -p ~/Vaults`
- [ ] Open Obsidian → Settings → Sync → sign in with your Obsidian account
- [ ] For each remote vault: pull to `~/Vaults/<vault-name>` via "Show vaults stored in Obsidian Sync"
- [ ] Verify bidirectional sync with the iPhone for one vault (edit on phone → appears on freeMac, and vice versa)
- [ ] `ls ~/Vaults && du -sh ~/Vaults` — confirm all vaults present and total size sane

### Phase 2.5 — Syncthing (bridge freeBox ↔ freeMac)

- [ ] `brew install syncthing`
- [ ] `brew services start syncthing`
- [ ] Open Syncthing GUI at `http://127.0.0.1:8384`
- [ ] Add freeBox as a remote device (use its Syncthing device ID)
- [ ] Share `~/Vaults` folder with freeBox (`sendreceive` mode)
- [ ] Copy `.stignore` from freeBox (or match the `(?d)` patterns from the existing setup)
- [ ] Verify bidirectional sync: edit a file on freeBox → appears on freeMac, and vice versa
- [ ] Confirm Syncthing runs over Tailscale (devices should find each other via tailnet IPs)

### Phase 3 — Claude Code + per-vault remote-control sessions

- [ ] Install Claude Code: `curl -fsSL https://claude.ai/install.sh | bash && claude --version`
- [ ] `brew install tmux`
- [ ] First interactive `claude` run to complete the browser auth flow (must happen before the LaunchAgent fires)
- [ ] Clone this repo: `mkdir -p ~/Vaults && cd ~/Vaults && git clone https://github.com/dreamspy/freeBox.git`
- [x] Update `mac-workstation-up.sh` to use `claude remote-control --name "freemac-<sanitized-vault>"` instead of plain `claude` (matching the `freebox-vaults-up.sh` pattern: transliterate Unicode via `iconv`, lowercase, collapse non-alnum to `_`, pre-trust vault dirs in `~/.claude.json`)
- [ ] Run `bash ~/Vaults/freeBox/20_scripts/mac-workstation-up.sh` — verify `tmux ls` shows one `vault-<name>` session per vault, each running `claude remote-control --name "freemac-<name>"`
- [ ] Pair iPhone Claude Code Remote Control with at least one session — should show up as `freemac-<vault>` in the iPhone app (distinct from `freebox-<vault>` sessions)

### Phase 4 — Auto-start after login

- [ ] Install the LaunchAgent at `~/Library/LaunchAgents/com.freebox.mac-workstation.plist` (heredoc in runbook §4.1)
- [ ] `launchctl load` it
- [ ] Test by killing `tmux` and Obsidian, then unloading + reloading the agent (runbook §4.2)
- [ ] Real reboot test: `sudo reboot` → type FileVault password → confirm sessions and Obsidian windows come back automatically within ~10 seconds

### Phase 5 — Backup ~/Vaults on this Mac (safety net before cross-device testing)

- [ ] Verify `~/Backups/Vaults-pre-syncthing-2026-04-09.tar.gz` still exists. If not: `tar -czf ~/Backups/Vaults-$(date +%F).tar.gz -C ~ Vaults`
- [ ] Confirm the tarball is complete and non-empty: `ls -lh ~/Backups/Vaults-*.tar.gz`

### Phase 6 — Cross-device sync and edit test

- [ ] **Test 1 — iPhone → freeMac:** edit a note in Obsidian on the iPhone → verify it appears on freeMac (via Obsidian Sync)
- [ ] **Test 2 — freeMac → iPhone:** edit a note on freeMac (via Obsidian or Claude) → verify it appears on the iPhone
- [ ] **Test 3 — freeBox → this Mac:** edit a note via Claude on freeBox → verify it appears on this Mac (via Syncthing)
- [ ] **Test 4 — iPhone → freeBox (via SilverBullet):** edit a note in the SilverBullet PWA → verify it appears on freeBox and on this Mac
- [ ] **Test 5 — Claude on freeMac → iPhone:** ask Claude in a `freemac-<vault>` session to create a test page → verify it shows up on the iPhone via Obsidian Sync
- [ ] **Test 6 — Full round trip:** edit on one device → confirm it reaches all others within 1–2 minutes
- [ ] Document any conflicts, `.sync-conflict-*` files, or propagation delays

### Phase 7 — Decide whether this is permanent

- [ ] Use the setup for a few weeks of normal work
- [ ] Decide: keep freeMac as primary, go back to freeBox, or hybrid
- [ ] Update `10_docs/obsidian-sync.md` and the freeBox sections of this TODO with the result
- [ ] (If keeping freeMac) revisit freeBox's role — backup workstation, SilverBullet host, build box, retire?

### Optional hardening

- [ ] Put freeMac on a small UPS to eliminate brief power outages


## Later / nice to have

- [ ] Decide whether to enable Tailscale SSH (`sudo tailscale up --ssh`) — eliminates manual SSH key management for the private path
- [ ] Disable Tailscale key expiry on freeBox in the [admin console](https://login.tailscale.com/admin/machines) so it doesn't drop off the tailnet after 180 days

---

## Archive (completed)

### freeBox initial provisioning

- [x] Provision Linode VPS (Ubuntu 24.04 LTS)
- [x] SSH access via `~/.ssh/config` alias `freebox`
- [x] Install Tailscale and join the tailnet (Tailscale IP in `SECRETS.md`)
- [x] Clean up `~/.ssh/config` (route `freebox` via Tailscale by default, public IP as commented fallback)
- [x] Reboot freeBox if a kernel update is pending
- [x] `sudo apt update && sudo apt upgrade -y`
- [x] Install base tools (`tmux`, `git`, `curl`, `wget`, `unzip`, `ripgrep`, `fd-find`, `zsh`, `htop`, `build-essential`, `ufw`)
- [x] `sudo timedatectl set-timezone Atlantic/Reykjavik`
- [x] Install Claude Code
- [x] Authenticate Claude (browser login flow)
- [x] Start persistent session: `tmux new -s claude`
- [x] Test Claude Remote Control from iPhone
- [x] `mkdir -p ~/work`
- [x] Enable firewall: `sudo ufw allow OpenSSH && sudo ufw enable`
- [x] Verify: `sudo ufw status verbose`
- [x] Harden `/etc/ssh/sshd_config` (`PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes`)
- [x] Run `check-health.sh` — all green

### Vaults on freeBox (Syncthing + per-vault Claude sessions)

> Decided 2026-04-09. Vaults at `~/Vaults/<vault>/`, synced via Syncthing. See [`10_docs/obsidian-sync.md`](10_docs/obsidian-sync.md) and [`10_docs/freebox-services.md`](10_docs/freebox-services.md).

- [x] Decide on sync strategy — Syncthing
- [x] Vaults onto freeBox via Syncthing peering with the Mac
- [x] Per-vault Claude sessions via `freebox-vaults-up.sh` (`claude remote-control --name "freebox-<vault>"`)
- [x] Document naming convention in script header and `freebox-services.md`
- [x] Enable lingering: `sudo loginctl enable-linger frimann`
- [x] Verify auto-start after real reboot — confirmed 2026-04-09
- [x] `.stignore` with `(?d)` prefixes for volatile patterns

### SilverBullet on freeBox

> Added 2026-04-09. iOS-friendly markdown editor. See [`10_docs/silverbullet.md`](10_docs/silverbullet.md).

- [x] Install Docker on freeBox
- [x] Generate SilverBullet password, store in `SECRETS.md` and `~/.silverbullet.env`
- [x] Run `silverbullet` container bound to `127.0.0.1:3000`
- [x] `tailscale serve` mount `/` → SilverBullet
- [x] Verify HTTPS from Mac browser
- [x] Install SilverBullet PWA on iPhone
- [x] `sb-switch` script for per-vault switching
- [x] `sb-launcher.py` vault picker web app
- [x] `sb-launcher.service` (systemd)
- [x] `tailscale serve` mount `/launcher` → launcher
- [x] Install launcher PWA on iPhone
- [x] Web App Manifest with `start_url=/launcher`
