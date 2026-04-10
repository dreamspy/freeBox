# Mac always-on workstation runbook

End-to-end provisioning for **freeMac**, a MacBook Pro (M1, fresh macOS install) used as a 24/7 always-on workstation. It runs per-vault Claude Code Remote Control sessions in tmux, Obsidian Sync (bridge to freePhone when atom is off), and Syncthing (peer mesh with freeBox and atom).

## Machines

| Name          | Role                                                                                                               |
| ------------- | ------------------------------------------------------------------------------------------------------------------ |
| **freePhone** | iPhone; edits via Obsidian, SilverBullet PWA, Claude Remote Control                                                |
| **freeBox**   | Linode VPS; runs SilverBullet, Syncthing to atom and freeMac                                                       |
| **atom**      | Day-to-day MacBook; Obsidian, Claude CLI, Claude Desktop remote, Syncthing + Obsidian Sync                         |
| **freeMac**   | Always-on Mac "server"; Obsidian Sync (bridge to freePhone when atom is off), Syncthing, Claude CLI remote in tmux |

## Sync topology

```
freeBox ⇄ Syncthing ⇄ freeMac ⇄ Obsidian Sync ⇄ freePhone
    ↑        ⇅                     Obsidian Sync ⇄ atom
    ↑    Syncthing ⇄ atom
SilverBullet (freePhone PWA)
```

Both Macs run Syncthing (peer mesh with freeBox) + Obsidian Sync. freeMac is the always-on bridge; atom syncs when awake.

---

## 0. Assumptions and decisions

- **Hardware:** MacBook Pro, Apple Silicon (M1)
- **OS:** fresh install of macOS
- **FileVault:** **ON** — accepted tradeoff is one manual password entry after every actual reboot. Everything else (sessions, Obsidian, Tailscale) auto-starts after the FileVault unlock and the auto-login that follows it
- **Lid:** start with the lid open on a desk; transition to lid-closed later with Amphetamine when needed (covered in §1.2)
- **Vaults:** all live in `~/Vaults/<vault-name>/`, synced via **Obsidian Sync** (to freePhone and atom) and **Syncthing** (to freeBox and atom)
- **Sessions:** one tmux session per vault, named `freemac-<sanitized-vault-name>`, each running `claude remote-control --name "freemac-<name>"`
- **Phone access:** Claude Code Remote Control for the Claude sessions (tunnels through Anthropic, no VPN required); Tailscale on the Mac for everything else (SSH, future web services, Files)
- **Repo location on the Mac:** `~/Vaults/freeBox` (clone this repo here so the helper script and the LaunchAgent paths line up). Override with `VAULTS_DIR` env var if you keep vaults elsewhere
- **Helper scripts:** `20_scripts/mac-workstation-up.sh` (Claude tmux + Obsidian), `20_scripts/mac-obsidian-up.sh` (Obsidian-only, lighter option)

> **About FileVault:** macOS does not allow auto-login when FileVault is on. After any actual reboot or power failure, the Mac comes back to the FileVault unlock screen and waits for you to physically type your account password. Once you type it, the user auto-logs in and the LaunchAgent installed in §4 fires and brings everything else back. A small UPS (~$40) eliminates the most common cause of unattended reboots and is the right lever to pull rather than disabling FileVault. See `10_docs/obsidian-sync.md` and the project memory for the broader notes-workflow context.

> **Adding a new vault:** Obsidian Sync has no "sync all" — each new remote vault must be manually pulled on freeMac via the Obsidian GUI (vault picker → "Show vaults stored in Obsidian Sync" → set path to `~/Vaults/<name>`). This is the one unavoidable manual step. Syncthing will pick up the new folder automatically once it exists.

---

## 1. Power management — keep the Mac awake

### 1.1 `pmset` settings

Run once. All flags are reversible — `pmset -g` shows current values.

```bash
sudo pmset -a sleep 0          # never put the system to sleep
sudo pmset -a disksleep 0      # never spin down internal storage
sudo pmset -a displaysleep 10  # let the display sleep after 10 min (cosmetic)
sudo pmset -a powernap 1       # keep Power Nap on
sudo pmset -a womp 1           # wake on network (magic packet)
sudo pmset -a autorestart 1    # auto-restart after a power failure
sudo pmset -a hibernatemode 0  # do not hibernate to disk
```

Verify:

```bash
pmset -g
```

> Some of these flags are silently ignored on Apple Silicon. That's expected — `pmset` is shared across architectures. If you'd rather keep the display always on, set `displaysleep 0`.

### 1.2 Lid behavior

- **Lid open on a desk (start here):** the `pmset` settings above are sufficient. No extra software.
- **Lid closed without an external display (transition to later):** macOS hard-sleeps on lid close in this configuration and `pmset` has no flag for it. Install **Amphetamine** (free, App Store) and enable its "lid closed" trigger. Skip this until you're actually moving to lid-closed.
- **Lid closed with an external display (clamshell):** also works without extra software, but requires power + an external display + an external keyboard/mouse plugged in.

### 1.3 Battery

Apple Silicon's *Optimized Battery Charging* parks the battery near 80% most of the time when the Mac is plugged in continuously. Leave it plugged in. Don't manually exercise the battery — it makes things worse, not better.

### 1.4 Tailscale on the Mac

```bash
brew install --cask tailscale
```

Sign in via the menu bar icon to the same tailnet as freeBox, atom, and freePhone. Verify:

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale ip -4
```

(The Mac App Store version of Tailscale is also fine if you prefer sandboxed installs — pick one.)

### 1.5 Screen Sharing (VNC over Tailscale)

**System Settings → General → Sharing → Screen Sharing → On.**

This lets you get a full GUI session on freeMac from any other device on the tailnet. No port forwarding or public exposure — Tailscale handles the tunnel.

Connect from atom:

```bash
open vnc://freemac
```

Or use **Finder → Go → Connect to Server → `vnc://freemac`**.

> Screen Sharing only works while macOS is logged in. If freeMac is stuck at the FileVault screen after a reboot, you must type the password physically — VNC cannot reach the pre-boot unlock screen.

### 1.6 Verify Phase 1

- `pmset -g` shows the values from §1.1
- freeMac's tailnet IPv4 is reachable from freePhone (`tailscale ping freemac` from another tailnet device, or just SSH/HTTP-test)
- After 30 minutes idle: the display sleeps but the system stays up and reachable
- `uptime` keeps growing across the day

---

## 2. Vaults via Obsidian Sync

**Goal:** every vault from your Obsidian Sync account lives at `~/Vaults/<name>/` on the Mac and is bidirectionally synced with freePhone (and atom when awake).

### 2.1 Install Obsidian and create the vaults root

```bash
brew install --cask obsidian
mkdir -p ~/Vaults
```

### 2.2 Sign in to Obsidian Sync

Open Obsidian. The vault picker is the first thing you see — open or create *any* throwaway vault first so Obsidian's settings panel becomes accessible. Then **Settings → Sync → sign in** with your Obsidian account.

### 2.3 Pull each vault to `~/Vaults/<name>`

Obsidian Sync has no "sync all my vaults" button — repeat once per vault. For each remote vault:

1. Vault picker → in the **"Show vaults stored in Obsidian Sync"** section, pick the remote vault
2. Set the local destination to `~/Vaults/<vault-name>`
3. Wait for the initial sync. With ~400 MB total across 5–10 vaults, each vault completes in seconds to a couple of minutes
4. Spot-check: edit a recent note on freePhone and watch it appear on freeMac (and vice versa)

After all vaults are pulled, `ls ~/Vaults` should list one subdirectory per vault, each with its own `.obsidian/` config folder.

### 2.4 Verify Phase 2

```bash
ls ~/Vaults
du -sh ~/Vaults
```

- Every expected vault is present
- Total size is in the ballpark of 400 MB
- A freePhone-side edit appears on freeMac within seconds, and vice versa

---

## 2.5. Syncthing (bridge freeBox ↔ freeMac)

**Goal:** freeMac peers with freeBox (and atom) via Syncthing over Tailscale, so edits made by Claude on freeBox propagate to freeMac → Obsidian Sync → freePhone, even when atom is off.

### 2.5.1 Install and start Syncthing

```bash
brew install syncthing
brew services start syncthing
```

### 2.5.2 Configure peering

1. Open the Syncthing GUI at `http://127.0.0.1:8384`
2. Add freeBox as a remote device (use its Syncthing device ID)
3. Share the `~/Vaults` folder with freeBox (`sendreceive` mode)
4. Copy `.stignore` from freeBox (or match the `(?d)` patterns from the existing setup)

### 2.5.3 Verify

- Edit a file on freeBox → appears on freeMac, and vice versa
- Confirm Syncthing runs over Tailscale (devices should find each other via tailnet IPs)

---

## 3. Claude Code with per-vault remote-control sessions

**Goal:** one always-on `claude remote-control` session per vault, named `freemac-<vault>` (matching the freeBox naming convention of `freebox-<vault>`), plus the helper script that creates them all in one shot.

### 3.1 Install the tools

```bash
curl -fsSL https://claude.ai/install.sh | bash
brew install tmux
claude --version
tmux -V
```

The first interactive `claude` run will prompt the browser auth flow — do that once now. Auto-started sessions in §4 cannot complete this flow themselves; the auth state must already exist on disk before the LaunchAgent fires.

### 3.2 Clone this repo

The helper script and LaunchAgent assume the repo is at `~/Vaults/freeBox`. If you keep vaults elsewhere, set `VAULTS_DIR` accordingly.

```bash
mkdir -p ~/Vaults
cd ~/Vaults
git clone https://github.com/dreamspy/freeBox.git
```

### 3.3 Run the helper script

The helper at `20_scripts/mac-workstation-up.sh` is idempotent — it skips sessions that already exist and opens any vault windows that aren't already open. Each session runs `claude remote-control --name "freemac-<sanitized-vault>"` (Unicode transliterated via `iconv`, lowercased, non-alnum collapsed to `_`).

```bash
	bash ~/Vaults/freeBox/20_scripts/mac-workstation-up.sh
```

You should see one detached tmux session per vault and Obsidian opening one window per vault.

Inspect:

```bash
tmux ls
```

Reattach a single session:

```bash
tmux attach -t freemac-<name>
```

Detach without killing it: `Ctrl-b` then `d`.

There is also a lighter script `20_scripts/mac-obsidian-up.sh` that only opens Obsidian windows without starting Claude sessions.

### 3.4 Connect Claude Code Remote Control from freePhone

Important: Claude Code Remote Control **does not require Tailscale**. It tunnels through Anthropic's infrastructure and works over the public internet directly. Sessions show up as `freemac-<vault>` in the Claude Code app (distinct from `freebox-<vault>` sessions on freeBox).

Tailscale on freePhone is still useful for *everything else* (SSH from Blink/Termius, hitting any future local web service, Files), but the Remote Control feature itself does not need it.

### 3.5 Verify Phase 3

- `tmux ls` shows one `freemac-<name>` session per vault
- Each session has a running `claude remote-control` process (`tmux attach -t freemac-<name>` to spot-check)
- Obsidian has one window open per vault
- freePhone Claude Code app can attach to at least one session — should show up as `freemac-<vault>`

---

## 4. Auto-start everything after login

**Goal:** after every reboot, once you've typed the FileVault password, freeMac brings tmux sessions and Obsidian windows back without any further intervention.

> Two helper scripts are available: `mac-workstation-up.sh` (Claude tmux + Obsidian) and `mac-obsidian-up.sh` (Obsidian-only). Use whichever fits; the LaunchAgent below uses the full version.

### 4.1 Install the LaunchAgent

This writes the plist using your current `$HOME` so there's nothing to hand-edit:

```bash
mkdir -p ~/Library/LaunchAgents ~/Library/Logs

cat > ~/Library/LaunchAgents/com.freebox.mac-workstation.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.freebox.mac-workstation</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$HOME/Vaults/freeBox/20_scripts/mac-workstation-up.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/mac-workstation.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/mac-workstation.log</string>
</dict>
</plist>
EOF

launchctl load ~/Library/LaunchAgents/com.freebox.mac-workstation.plist
```

### 4.2 Test the auto-start path without rebooting

```bash
# Stop any running sessions and close Obsidian windows so we have a clean test
tmux kill-server 2>/dev/null || true
osascript -e 'quit app "Obsidian"' 2>/dev/null || true

# Trigger the LaunchAgent manually
launchctl unload ~/Library/LaunchAgents/com.freebox.mac-workstation.plist
launchctl load ~/Library/LaunchAgents/com.freebox.mac-workstation.plist

# Check the log
tail -n 50 ~/Library/Logs/mac-workstation.log
tmux ls
```

If `tmux ls` shows the per-vault sessions and Obsidian opened the vault windows, the LaunchAgent works.

### 4.3 Real reboot test

When you're ready to verify the full chain:

1. `sudo reboot`
2. Wait for the FileVault unlock screen
3. Type your account password
4. Within ~10 seconds you should see Obsidian windows open and `tmux ls` (in a new terminal) should show the sessions

This is the steady-state recovery flow for any future reboot.

### 4.4 Disabling auto-start

```bash
launchctl unload ~/Library/LaunchAgents/com.freebox.mac-workstation.plist
rm ~/Library/LaunchAgents/com.freebox.mac-workstation.plist
```

---

## 5. Backup ~/Vaults (rsync snapshots)

**Goal:** periodic local backup so a bad sync event or accidental deletion doesn't destroy vault data.

Set up periodic rsync snapshot of `~/Vaults` to a local backup location:

```bash
mkdir -p ~/Backups
rsync -a --delete ~/Vaults/ ~/Backups/Vaults-$(date +%F)/
```

Verify:

```bash
ls -lh ~/Backups/
```

Spot-check a vault to confirm it's complete and restorable.

---

## 6. Cross-device sync verification

**Goal:** confirm end-to-end sync works across all four machines in both directions.

| Test | Path | What to verify |
|------|------|----------------|
| **1 — freeBox outward** | Edit on freeBox → Syncthing → atom + freeMac → Obsidian Sync → freePhone | File arrives on all devices |
| **2 — freePhone outward** | Edit on freePhone → Obsidian Sync → atom + freeMac → Syncthing → freeBox | File arrives on all devices |
| **3 — atom off, freeBox → freePhone** | Shut atom's lid. Edit on freeBox → Syncthing → freeMac → Obsidian Sync → freePhone | This is the reason freeMac exists |
| **4 — SilverBullet path** | Edit on freePhone via SilverBullet PWA → freeBox disk → Syncthing → atom + freeMac | File fans out via Syncthing |
| **5 — Conflict handling** | Edit same file on two devices simultaneously | One wins, other produces `.sync-conflict-*` file (or merges cleanly) |

Document any propagation delays observed.

---

## 7. Day-to-day cheat sheet

```bash
tmux ls                                # which sessions are alive
tmux attach -t freemac-<name>          # work on a vault's claude session
# Ctrl-b d                             # detach without killing

bash ~/Vaults/freeBox/20_scripts/mac-workstation-up.sh   # idempotent: bring missing sessions/windows back
bash ~/Vaults/freeBox/20_scripts/mac-obsidian-up.sh      # lighter: Obsidian windows only
tail -f ~/Library/Logs/mac-workstation.log               # debug auto-start
```

Periodic maintenance:

```bash
softwareupdate --list                                # are macOS updates pending?
brew update && brew upgrade                          # keep brew current
claude --version                                     # confirm Claude still works after updates
```

---

## 8. Common failures

**`launchctl load` succeeds but nothing runs at login** — the script's `$PATH` doesn't include Homebrew or the Claude install dir. The helper script exports a hard-coded `PATH` for exactly this reason; check `~/Library/Logs/mac-workstation.log` for the error.

**Sessions exist but `claude` is stuck at the auth prompt** — you skipped §3.1's "first interactive `claude` run." Auth state has to be on disk before the LaunchAgent fires. Run `claude` in a normal terminal once, complete the browser flow, then re-run the LaunchAgent.

**Obsidian opens but vaults don't appear** — Obsidian Sync hasn't finished pulling them, or the local destination directories don't match `~/Vaults/<name>/`. Open Obsidian manually and check the Sync settings.

**Tailscale ping from another device fails** — Mac woke from display sleep but the network stack is still settling, or the Tailscale app isn't logged in. Click the menu bar icon, confirm "Connected," and retry.

**Conflict files (`*.sync-conflict-*.md`) appear in a vault** — two devices edited the same note while temporarily out of sync. Open the conflict file and the original side by side, merge by hand, delete the conflict file. Rare in single-user setups.

**After a power failure the Mac is unreachable** — expected: it's sitting at the FileVault unlock screen waiting for you. Walk to it, type the password, the rest auto-starts. A UPS prevents the common case.

**Claude session eats CPU forever** — `tmux attach -t freemac-<name>`, `Ctrl-c` in the Claude prompt, then exit. Re-run the helper script to bring it back.

---

## 9. Validation checklist

After working through everything above:

- [ ] `pmset -g` shows `sleep 0`, `disksleep 0`, `womp 1`, `autorestart 1`
- [ ] Tailscale is installed, signed in, and freeMac's tailnet IP is reachable from freePhone
- [ ] `~/Vaults` contains every expected vault, each with a `.obsidian/` folder
- [ ] Syncthing is running and peered with freeBox (and atom)
- [ ] `tmux ls` shows one `freemac-<name>` session per vault
- [ ] Each session has a running `claude remote-control` process
- [ ] Obsidian has one window per vault
- [ ] `~/Library/LaunchAgents/com.freebox.mac-workstation.plist` exists and `launchctl list | grep mac-workstation` shows it loaded
- [ ] freePhone Claude Code app pairs with at least one session (showing as `freemac-<vault>`)
- [ ] After a real `sudo reboot` and FileVault unlock, sessions and Obsidian windows come back automatically
- [ ] Cross-device sync tests (§6) pass

---

## 10. Deciding freeMac's permanent role

After a few weeks of running this setup, decide:

- **Keep freeMac as the always-on bridge.** Update `10_docs/obsidian-sync.md` and `TODO.md` to reflect that decision. Decide what role freeBox plays going forward (SilverBullet host only, backup workstation, retired).
- **Go back to freeBox only.** Document why this didn't fit. Move the runbook out of the active path but keep it for reference.
- **Hybrid.** Some vaults on the Mac, some classes of work on freeBox. Pick the boundary explicitly and write it down.
