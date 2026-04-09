# Mac always-on workstation runbook

End-to-end provisioning for a MacBook Pro (M1, fresh macOS install) being used as a 24/7 workstation that runs Claude Code sessions for multiple Obsidian vaults, accessible from the iPhone via Claude Code Remote Control and Tailscale.

**Current decision (2026-04-09, provisional):** the Mac is being tested in this role for a few weeks before deciding whether it permanently replaces freeBox for this workload. While this experiment runs, freeBox stays up but unused for vault work.

---

## 0. Assumptions and decisions

- **Hardware:** MacBook Pro, Apple Silicon (M1)
- **OS:** fresh install of macOS
- **FileVault:** **ON** — accepted tradeoff is one manual password entry after every actual reboot. Everything else (sessions, Obsidian, Tailscale) auto-starts after the FileVault unlock and the auto-login that follows it
- **Lid:** start with the lid open on a desk; transition to lid-closed later with Amphetamine when needed (covered in §1.2)
- **Vaults:** all live in `~/vaults/<vault-name>/`, all bidirectionally synced via the existing **Obsidian Sync** subscription
- **Sessions:** one tmux session per vault, named `vault-<name>`, each running `claude` in the vault's directory
- **Phone access:** Claude Code Remote Control for the Claude sessions (tunnels through Anthropic, no VPN required); Tailscale on the Mac for everything else (SSH, future web services, Files)
- **Repo location on the Mac:** `~/Programming/freeBox` (clone this repo here so the helper script and the LaunchAgent paths line up). Override with `REPO_DIR` if you keep it elsewhere

> **About FileVault:** macOS does not allow auto-login when FileVault is on. After any actual reboot or power failure, the Mac comes back to the FileVault unlock screen and waits for you to physically type your account password. Once you type it, the user auto-logs in and the LaunchAgent installed in §4 fires and brings everything else back. A small UPS (~$40) eliminates the most common cause of unattended reboots and is the right lever to pull rather than disabling FileVault. See `10_docs/obsidian-sync.md` and the project memory for the broader notes-workflow context.

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

Sign in via the menu bar icon to the same tailnet as freeBox and the iPhone. Verify:

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale ip -4
```

(The Mac App Store version of Tailscale is also fine if you prefer sandboxed installs — pick one.)

### 1.5 Verify Phase 1

- `pmset -g` shows the values from §1.1
- The Mac's tailnet IPv4 is reachable from the iPhone (`tailscale ping <mac>` from another tailnet device, or just SSH/HTTP-test)
- After 30 minutes idle: the display sleeps but the system stays up and reachable
- `uptime` keeps growing across the day

---

## 2. Vaults via Obsidian Sync

**Goal:** every vault from your Obsidian Sync account lives at `~/vaults/<name>/` on the Mac and is bidirectionally synced with the iPhone.

### 2.1 Install Obsidian and create the vaults root

```bash
brew install --cask obsidian
mkdir -p ~/vaults
```

### 2.2 Sign in to Obsidian Sync

Open Obsidian. The vault picker is the first thing you see — open or create *any* throwaway vault first so Obsidian's settings panel becomes accessible. Then **Settings → Sync → sign in** with your Obsidian account.

### 2.3 Pull each vault to `~/vaults/<name>`

Obsidian Sync has no "sync all my vaults" button — repeat once per vault. For each remote vault:

1. Vault picker → in the **"Show vaults stored in Obsidian Sync"** section, pick the remote vault
2. Set the local destination to `~/vaults/<vault-name>`
3. Wait for the initial sync. With ~400 MB total across 5–10 vaults, each vault completes in seconds to a couple of minutes
4. Spot-check: edit a recent note on the iPhone and watch it appear on the Mac (and vice versa)

After all vaults are pulled, `ls ~/vaults` should list one subdirectory per vault, each with its own `.obsidian/` config folder.

### 2.4 Verify Phase 2

```bash
ls ~/vaults
du -sh ~/vaults
```

- Every expected vault is present
- Total size is in the ballpark of 400 MB
- An iPhone-side edit appears on the Mac within seconds, and vice versa

---

## 3. Claude Code with one tmux session per vault

**Goal:** one always-on `claude` session per vault, plus the helper script that creates them all in one shot.

### 3.1 Install the tools

```bash
curl -fsSL https://claude.ai/install.sh | bash
brew install tmux
claude --version
tmux -V
```

The first interactive `claude` run will prompt the browser auth flow — do that once now. Auto-started sessions in §4 cannot complete this flow themselves; the auth state must already exist on disk before the LaunchAgent fires.

### 3.2 Clone this repo

The helper script and LaunchAgent assume the repo is at `~/Programming/freeBox`. If you keep it elsewhere, set `REPO_DIR` accordingly throughout this doc.

```bash
mkdir -p ~/Programming
cd ~/Programming
git clone https://github.com/dreamspy/freeBox.git
```

### 3.3 Run the helper script

The helper at `20_scripts/mac-workstation-up.sh` is idempotent — it skips sessions that already exist and opens any vault windows that aren't already open.

```bash
bash ~/Programming/freeBox/20_scripts/mac-workstation-up.sh
```

You should see one detached tmux session per vault and Obsidian opening one window per vault.

Inspect:

```bash
tmux ls
```

Reattach a single session:

```bash
tmux attach -t vault-<name>
```

Detach without killing it: `Ctrl-b` then `d`.

### 3.4 Connect Claude Code Remote Control from the iPhone

Important: Claude Code Remote Control **does not require Tailscale**. It tunnels through Anthropic's infrastructure and works over the public internet directly. From inside any tmux session:

```
/remote-control
```

Follow the URL/QR flow to pair the iPhone Claude Code app with that specific session. Repeat per session you want phone access to.

Tailscale on the iPhone is still useful for *everything else* (SSH from Blink/Termius, hitting any future local web service, Files), but the Remote Control feature itself does not need it.

### 3.5 Verify Phase 3

- `tmux ls` shows one `vault-<name>` session per vault
- Each session has a running `claude` process (`tmux attach -t vault-<name>` to spot-check)
- Obsidian has one window open per vault
- The iPhone Claude Code app can attach to at least one session via Remote Control

---

## 4. Auto-start everything after login

**Goal:** after every reboot, once you've typed the FileVault password, the Mac brings tmux sessions and Obsidian windows back without any further intervention.

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
    <string>$HOME/Programming/freeBox/20_scripts/mac-workstation-up.sh</string>
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

## 5. Day-to-day cheat sheet

```bash
tmux ls                                # which sessions are alive
tmux attach -t vault-<name>            # work on a vault's claude session
# Ctrl-b d                             # detach without killing

bash ~/Programming/freeBox/20_scripts/mac-workstation-up.sh   # idempotent: bring missing sessions/windows back
tail -f ~/Library/Logs/mac-workstation.log                    # debug auto-start
```

Periodic maintenance:

```bash
softwareupdate --list                                # are macOS updates pending?
brew update && brew upgrade                          # keep brew current
claude --version                                     # confirm Claude still works after updates
```

---

## 6. Common failures

**`launchctl load` succeeds but nothing runs at login** — the script's `$PATH` doesn't include Homebrew or the Claude install dir. The helper script exports a hard-coded `PATH` for exactly this reason; check `~/Library/Logs/mac-workstation.log` for the error.

**Sessions exist but `claude` is stuck at the auth prompt** — you skipped §3.1's "first interactive `claude` run." Auth state has to be on disk before the LaunchAgent fires. Run `claude` in a normal terminal once, complete the browser flow, then re-run the LaunchAgent.

**Obsidian opens but vaults don't appear** — Obsidian Sync hasn't finished pulling them, or the local destination directories don't match `~/vaults/<name>/`. Open Obsidian manually and check the Sync settings.

**Tailscale ping from another device fails** — Mac woke from display sleep but the network stack is still settling, or the Tailscale app isn't logged in. Click the menu bar icon, confirm "Connected," and retry.

**Conflict files (`*.sync-conflict-*.md`) appear in a vault** — two devices edited the same note while temporarily out of sync. Open the conflict file and the original side by side, merge by hand, delete the conflict file. Rare in single-user setups.

**After a power failure the Mac is unreachable** — expected: it's sitting at the FileVault unlock screen waiting for you. Walk to it, type the password, the rest auto-starts. A UPS prevents the common case.

**Claude session eats CPU forever** — `tmux attach -t vault-<name>`, `Ctrl-c` in the Claude prompt, then exit. Re-run the helper script to bring it back.

---

## 7. Validation checklist

After working through everything above:

- [ ] `pmset -g` shows `sleep 0`, `disksleep 0`, `womp 1`, `autorestart 1`
- [ ] `tailscale` is installed, signed in, and the Mac's tailnet IP is reachable from the iPhone
- [ ] `~/vaults` contains every expected vault, each with a `.obsidian/` folder
- [ ] `tmux ls` shows one `vault-<name>` session per vault
- [ ] Each session has a running `claude` process
- [ ] Obsidian has one window per vault
- [ ] `~/Library/LaunchAgents/com.freebox.mac-workstation.plist` exists and `launchctl list | grep mac-workstation` shows it loaded
- [ ] iPhone Claude Code app pairs with at least one session via `/remote-control`
- [ ] After a real `sudo reboot` and FileVault unlock, sessions and Obsidian windows come back automatically

---

## 8. When this experiment ends

After a few weeks of running this setup, decide:

- **Keep the Mac as the primary always-on workstation.** Update `10_docs/obsidian-sync.md` and `TODO.md` to reflect that decision. Decide what role freeBox plays going forward (backup workstation, code/build box, retired).
- **Go back to freeBox.** Document why this didn't fit. Move the runbook out of the active path but keep it for reference.
- **Hybrid.** Some vaults on the Mac, some classes of work on freeBox. Pick the boundary explicitly and write it down.
