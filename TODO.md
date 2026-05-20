# freeBox setup TODO

Working checklist for getting freeBox into a fully usable state. Detailed steps live in [`10_docs/setup.md`](10_docs/setup.md).

## Next up

- [ ] **freeMac reboot + test:** `sudo reboot` → type FileVault password → confirm within ~10 seconds that all 8 `vault-<name>` tmux sessions return and Obsidian reopens all 8 vaults. Any stragglers should be revived within ~60s by the `com.freebox.mac-tmux-ensure` watchdog — tail `~/Library/Logs/mac-tmux-ensure.log` to confirm. If a Claude session hangs at auth, run `claude` once interactively and repeat. (Also ticks the Phase 4 "Real reboot test" item below.)

- [ ] **Investigate freeMac LaunchAgent context auth failure** (2026-05-20). `claude remote-control --spawn=same-dir --name fm-...` succeeds when launched from an interactive ssh shell but fails with `401 — Remote Control is only available with claude.ai subscriptions` when launched from the `com.freebox.mac-tmux-ensure` LaunchAgent. Same binary, same credentials file, same args, same `HOME`/`USER`/`PATH`. Diagnostic dump showed the only env differences were SSH_CLIENT/LANG (in ssh) vs XPC_FLAGS/XPC_SERVICE_NAME (in launchd). Verified: account is `claude_max` subscription with valid OAuth token. **Workaround in place:** manually launched 8 tmux sessions from an interactive ssh shell on 2026-05-20 ~11:11; they're stable but won't be recreated under launchd until this is fixed. Per-vault respawn logs at `~/Library/Logs/freemac-vaults/<vault>.log` (added same date). **Next probes to try:** (a) TCC/sandbox permissions — check `tccutil` and Full Disk Access for `bash`/`claude`; (b) does claude send some XPC/launchd-derived identifier the server rejects; (c) reproduce by running `launchctl asuser <uid> claude remote-control ...` as root to confirm launchd-context is the variable; (d) check if `claude --debug` or `DEBUG=1 claude` reveals the auth path being chosen.

## Repo migration — atom pending

> freeMac and freeBox moved to `~/Programming/freeBox` on 2026-04-18. Atom is still at `~/Vaults/freeBox`; Syncthing is paused on all three peers until atom catches up.

- [x] **On atom:** add a `freeBox` block to `~/Vaults/.stignore` (local-only, not synced), then `mkdir -p ~/Programming && mv ~/Vaults/freeBox ~/Programming/freeBox`.
- [x] **On atom:** copy the Claude Code project slug so memory + session history follow the repo: `cp -a ~/.claude/projects/-Users-frimann-Vaults-freeBox ~/.claude/projects/-Users-frimann-Programming-freeBox` (adjust the slug to whatever atom's username/home resolves to). (Destination already existed from a prior session; merged via `rsync -a --ignore-existing` — 3 new session `.jsonl` files added, existing `memory/` preserved, source slug removed.)
- [x] **On atom:** check `~/Library/LaunchAgents/com.freebox.mac-workstation.plist` — if present, swap `Vaults/freeBox` → `Programming/freeBox` in the plist and `launchctl unload && launchctl load` it. (If absent, nothing to do — the doc template already points at the new path.) (No plist present on atom — nothing to do.)
- [x] **All three peers:** unpause Syncthing, then watch each peer's Syncthing UI for ~10 minutes to confirm no cross-peer deletion of `freeBox/`.
- [x] **Optional cleanup:** delete leftover `.sync-conflict-*.md` files on freeBox (`~/Programming/freeBox/TODO.sync-conflict-*.md`, `~/Programming/freeBox/10_docs/mac-workstation.sync-conflict-*.md`) — historical artifacts from before the move. (Deleted 2026-05-13; content was pre-migration superseded versions.)

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

## freeMac setup (M1 MacBook Pro as 24/7 Claude + Obsidian + Syncthing workstation)

> MacBook Pro (M1) called **freeMac**. Runs Obsidian Sync (bridge to freePhone when atom is off), Syncthing (peer mesh with freeBox and atom), and per-vault Claude remote-control sessions in tmux (same pattern as freeBox). Full runbook: [`10_docs/mac-workstation.md`](10_docs/mac-workstation.md). Helper scripts: [`20_scripts/mac-workstation-up.sh`](20_scripts/mac-workstation-up.sh) (Claude tmux + Obsidian), [`20_scripts/mac-obsidian-up.sh`](20_scripts/mac-obsidian-up.sh) (Obsidian-only).
>
> **Machines:**
> - **freePhone** — iPhone; edits via Obsidian, SilverBullet PWA, Claude remote control (to freeBox)
> - **freeBox** — Linode VPS; runs SilverBullet, Syncthing to atom and freeMac
> - **atom** — day-to-day MacBook; Obsidian, Claude CLI, Claude Desktop remote (to freeBox/freeMac), Syncthing + Obsidian Sync
> - **freeMac** — always-on Mac "server"; Obsidian Sync (bridge to freePhone when atom is off), Syncthing, Claude CLI remote in tmux
>
> **Sync topology:**
> ```
> freeBox ⇄ Syncthing ⇄ freeMac ⇄ Obsidian Sync ⇄ freePhone
>     ↑        ⇅                     Obsidian Sync ⇄ atom
>     ↑    Syncthing ⇄ atom
> SilverBullet (freePhone PWA)
> ```
> Both Macs run Syncthing (peer mesh with freeBox) + Obsidian Sync.
> freeMac is the always-on bridge; atom syncs when awake.
>
> **Claude remote-control naming convention** (consistent across all machines):
> - freeBox sessions: `freebox-<vault-name>` (via `freebox-vaults-up.sh`)
> - freeMac sessions: `fm-<vault-name>` (via `mac-workstation-up.sh`)
>
> **Adding a new vault:** Obsidian Sync has no "sync all" — each new remote vault must be manually pulled on freeMac via the Obsidian GUI (vault picker → "Show vaults stored in Obsidian Sync" → set path to `~/Vaults/<name>`). This is the one unavoidable manual step.

### Phase 0 — Factory reset + macOS 26

- [x] Back up anything needed from the current install (if any)
- [x] Factory reset the M1 MacBook Pro (Erase All Content and Settings, or Recovery Mode reinstall)
- [x] Install macOS 26 (clean install)
- [x] Complete initial macOS setup (account, language, etc.)
- [x] Enable FileVault (accept tradeoff: one manual password entry after every reboot)

### Phase 1 — Base setup + power management

- [x] Set macOS hostname to `freeMac` (System Settings → General → Sharing → Local Hostname)
- [x] Apply `pmset` settings (`sleep 0`, `disksleep 0`, `womp 1`, `autorestart 1`, etc. — see runbook §1.1)
- [x] Verify with `pmset -g`
- [x] Plug Mac in permanently; trust Optimized Battery Charging
- [x] Install Homebrew: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
- [x] Install Tailscale: `brew install --cask tailscale`
- [x] Sign into the tailnet (same account as freeBox + iPhone), rename to `freemac` in the [admin console](https://login.tailscale.com/admin/machines)
- [x] Verify freeMac's tailnet IP is reachable from the iPhone and from this Mac
- [x] (Later, when going lid-closed) install Amphetamine and enable its lid-closed trigger

### Phase 2 — Vaults via Obsidian Sync

- [x] `brew install --cask obsidian`
- [x] `mkdir -p ~/Vaults`
- [x] Open Obsidian → Settings → Sync → sign in with your Obsidian account
- [x] For each remote vault: pull to `~/Vaults/<vault-name>` via "Show vaults stored in Obsidian Sync"
- [x] Verify bidirectional sync with the iPhone for one vault (edit on phone → appears on freeMac, and vice versa)
- [x] `ls ~/Vaults && du -sh ~/Vaults` — confirm all vaults present and total size sane

### Phase 2.5 — Syncthing (bridge freeBox ↔ freeMac)

- [x] `brew install syncthing`
- [x] `brew services start syncthing`
- [x] Open Syncthing GUI at `http://127.0.0.1:8384`
- [x] Add freeBox as a remote device (use its Syncthing device ID)
- [x] Share `~/Vaults` folder with freeBox (`sendreceive` mode)
- [x] Copy `.stignore` from freeBox (or match the `(?d)` patterns from the existing setup)
- [x] Verify bidirectional sync: edit a file on freeBox → appears on freeMac, and vice versa
- [x] Confirm Syncthing runs over Tailscale (devices should find each other via tailnet IPs)

### Phase 3 — Claude Code + per-vault remote-control sessions

- [x] Install Claude Code: `curl -fsSL https://claude.ai/install.sh | bash && claude --version`
- [x] `brew install tmux`
- [x] First interactive `claude` run to complete the browser auth flow (must happen before the LaunchAgent fires)
- [x] Clone this repo: `mkdir -p ~/Vaults && cd ~/Vaults && git clone https://github.com/dreamspy/freeBox.git`
- [x] Update `mac-workstation-up.sh` to use `claude remote-control --name "fm-<sanitized-vault>"` instead of plain `claude` (matching the `freebox-vaults-up.sh` pattern: transliterate Unicode via `iconv`, lowercase, collapse non-alnum to `_`, pre-trust vault dirs in `~/.claude.json`)
- [x] Run `bash ~/Programming/freeBox/20_scripts/mac-workstation-up.sh` — verify `tmux ls` shows one `vault-<name>` session per vault, each running `claude remote-control --name "fm-<name>"`
- [x] Pair freePhone Claude Code Remote Control with at least one session — should show up as `fm-<vault>` in the app (distinct from `freebox-<vault>` sessions)

### Phase 4 — Auto-start after login

> Three LaunchAgents on freeMac, all plists tracked in `20_scripts/com.freebox.*.plist`:
>
> 1. `com.freebox.mac-workstation` runs `mac-workstation-up.sh` at login. Brings up one tmux `claude remote-control` session per vault, plus one Obsidian window per vault.
> 2. `com.freebox.mac-tmux-ensure` runs `mac-tmux-ensure.sh` every 60s (`StartInterval=60`). Recreates missing `vault-*` tmux sessions. Added 2026-04-18 after observing sessions dying post-boot.
> 3. `com.freebox.mac-creds-watch` (added 2026-05-14): `WatchPaths` on `~/.claude/.credentials.json`. On change, runs `mac-creds-kick.sh`, which kills running `claude` processes, tears down `vault-*` tmux sessions, and re-runs `mac-tmux-ensure.sh`, so the next `/login` immediately refreshes all `claude remote-control` instances.
>
> See runbook §4 for install steps. `mac-obsidian-up.sh` is also available as a lighter alternative to #1 (Obsidian-only, no Claude tmux sessions); use it instead of #1 if you don't want Claude tmux sessions on this host.

- [x] Install the LaunchAgent at `~/Library/LaunchAgents/com.freebox.mac-workstation.plist` (heredoc in runbook §4.1)
- [x] `launchctl load` it
- [x] Test by killing `tmux` and Obsidian, then unloading + reloading the agent (runbook §4.2)
- [x] Install watchdog LaunchAgent `com.freebox.mac-tmux-ensure` (script `20_scripts/mac-tmux-ensure.sh`, logs `~/Library/Logs/mac-tmux-ensure.log`) — 2026-04-18
- [ ] Real reboot test: `sudo reboot` → type FileVault password → confirm sessions and Obsidian windows come back automatically within ~10 seconds, and that the watchdog revives any session that exits (check `mac-tmux-ensure.log` for restart lines)

### Phase 5 — Backup ~/Vaults (rsync snapshots)

- [ ] Set up periodic rsync snapshot of `~/Vaults` to a local backup location (e.g. `~/Backups/Vaults-<date>/`)
- [ ] Verify backup is complete and restorable: `ls -lh ~/Backups/` and spot-check a vault

### Phase 6 — Cross-device sync verification

> **Machines:** freePhone (iPhone), freeBox (Linode VPS), atom (day-to-day MacBook), freeMac (always-on Mac).

- [ ] **Test 1 — freeBox outward:** edit a file via Claude on freeBox → verify it arrives on atom (Syncthing) and freeMac (Syncthing) → verify it reaches freePhone (Obsidian Sync from either Mac)
- [ ] **Test 2 — freePhone outward:** edit in Obsidian on freePhone → verify it arrives on atom and freeMac (Obsidian Sync) → verify it reaches freeBox (Syncthing from either Mac)
- [ ] **Test 3 — atom off, freeBox → freePhone:** shut atom's lid or quit Obsidian+Syncthing. Edit on freeBox → Syncthing → freeMac → Obsidian Sync → freePhone. Verify the file arrives. (This is the reason freeMac exists.)
- [ ] **Test 4 — SilverBullet path:** edit on freePhone via SilverBullet PWA → lands on freeBox disk directly → verify it fans out via Syncthing to atom and freeMac
- [ ] **Test 5 — Conflict handling:** edit the same file on two devices simultaneously (e.g. atom + freeBox). Verify one wins and the other produces a `.sync-conflict-*` file (or merges cleanly). Document the behavior
- [ ] Document any propagation delays

### Phase 7 — Decide whether this is permanent

- [ ] Use the setup for a few weeks of normal work
- [ ] Decide: keep freeMac as primary, go back to freeBox, or hybrid
- [ ] Update `10_docs/obsidian-sync.md` and the freeBox sections of this TODO with the result
- [ ] (If keeping freeMac) revisit freeBox's role — backup workstation, SilverBullet host, build box, retire?

### Optional hardening

- [ ] Put freeMac on a small UPS to eliminate brief power outages


## Later / nice to have

- [ ] **Fallback for Claude Remote naming issues:** Set up Blink Shell (iOS) + Mosh as an alternative path to tmux sessions on freeBox/freeMac. Steps: install `mosh` on freeBox (`sudo apt install mosh`), install Blink Shell on freePhone, connect via `mosh freebox` over Tailscale, attach to tmux (Blink has native swipe gestures for tmux — no `ctrl+b` needed)
- [ ] Decide whether to enable Tailscale SSH (`sudo tailscale up --ssh`) — eliminates manual SSH key management for the private path
- [ ] Disable Tailscale key expiry on freeBox in the [admin console](https://login.tailscale.com/admin/machines) so it doesn't drop off the tailnet after 180 days

---

## Archive (completed)

### Credentials-change watchers (auto-restart on /login)

> Added 2026-05-14. On both hosts a watcher on `~/.claude/.credentials.json` kicks running `claude remote-control` processes when the file changes (typically after `claude /login`), so the respawn loop or watchdog picks up the fresh token within seconds instead of carrying the stale in-memory token until next reboot. Diagnosed after both freeBox and freeMac instances stopped responding to messages from the Claude app; the running processes had been holding tokens from 2-3 weeks earlier even though `~/.claude/.credentials.json` had been refreshed since. Trigger commits: `956cf4d` (freeBox respawn-name refresh), `de56b97` (watcher units for both hosts), `84e8bc8` (mac-creds-kick race fix).

- [x] freeBox: `20_scripts/freebox-claude-kick.path` + `.service` (systemd user units; `PathModified` on creds file triggers `pkill -x claude`; respawn loop in `freebox-vaults-up.sh` restarts within ~5s)
- [x] freeBox: `freebox-vaults-up.sh` wrapper re-evaluates `$(date +%m%d-%H%M)` per respawn so each kick produces a fresh `fb-<vault>-<MMdd-HHmm>` timestamp visible in the Claude app (was previously baked once at service start)
- [x] freeMac: `20_scripts/com.freebox.mac-creds-watch.plist` + `mac-creds-kick.sh` (LaunchAgent `WatchPaths` triggers a kicker that pkills claude, kills all `vault-*` tmux sessions synchronously, then re-runs `mac-tmux-ensure.sh`); the 60s `com.freebox.mac-tmux-ensure` watchdog catches any registration stragglers
- [x] LaunchAgent plists tracked in repo at `20_scripts/com.freebox.*.plist` with `<your-user>` placeholders and install instructions in XML comments (per the public-repo secret-handling rule in `CLAUDE.md`)
- [x] End-to-end verified on both hosts: `cp` round-trip on the creds file triggers the watcher; all 8 vault endpoints re-register with fresh timestamps

### Move repo out of ~/Vaults/ (Syncthing-synced)

> Completed on freeMac + freeBox 2026-04-18 (atom pending — see top of file). Repo now at `~/Programming/freeBox`. All script paths, user systemd units on freeBox, sb-launcher, and docs retargeted to the new path; path-migration commit is `9bb5545`.

- [x] Plan the move with Syncthing-safe ordering (per-peer `.stignore`, commit + push path updates first so peers can `git pull` before relocating)
- [x] Update scripts, systemd units, `sb-launcher.py`, and docs to reference `~/Programming/freeBox`
- [x] Commit + push path updates (`9bb5545`)
- [x] Add `freeBox` block to `~/Vaults/.stignore` on freeMac and freeBox
- [x] Move repo on freeMac and migrate Claude project slug (`-Users-frimann-Vaults-freeBox` → `-Users-frimann-Programming-freeBox`)
- [x] Move repo on freeBox: stop user units, `git fetch && reset --hard`, `mv`, reinstall updated unit files to `~/.config/systemd/user/`, `daemon-reload`, start; orphan `vault-freebox` tmux session auto-cleaned by `freebox-vaults-up.sh`
- [x] Redeploy `sb-launcher.py` on freeBox with updated `VAULTS_UP`; `sudo systemctl restart sb-launcher`
- [x] Migrate Claude project slug on freeBox (session `.jsonl` history copied; no `memory/` existed there)

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
