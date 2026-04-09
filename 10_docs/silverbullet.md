# SilverBullet on freeBox

How SilverBullet runs on freeBox, how to switch which vault it serves, and how the iOS PWA workflow is wired up. Companion to [`freebox-services.md`](freebox-services.md), which covers the running services from the "what is installed where" angle; this doc covers the "how to use it" and "why it's set up this way" angle.

## What it is and why it's here

[SilverBullet](https://silverbullet.md/) is a self-hosted, browser-based markdown notebook. On freeBox it's used as an **iOS-friendly editor** for the same vaults that Claude on freeBox can read/edit directly. The iPhone gets a PWA (`Add to Home Screen`) that opens fullscreen, looks like a native app, and edits files that live on freeBox under `~/Vaults/<vault>/` — the same files Syncthing keeps in sync with the Mac.

The motivating problem: Obsidian on iOS can only open vaults from local storage, iCloud, or Obsidian Sync — none of which reach a Linux server cleanly. SilverBullet plus a tailnet-only HTTPS endpoint sidesteps that.

## Architecture at a glance

```
iPhone (Tailscale + SB PWA + Launcher PWA)
   │      ▲
   │ HTTPS (tailnet only, valid Let's Encrypt cert from Tailscale)
   ▼      │
freebox.<tailnet>.ts.net  ─── tailscale serve ──┐
        │                                       │
        ├── /          → 127.0.0.1:3000  → SilverBullet container
        └── /launcher  → 127.0.0.1:3001  → sb-launcher (Python systemd service)

SilverBullet container is volume-mounted at /home/frimann/Vaults/<one vault>/
Launcher script swaps that mount via `sb-switch` (one container, one vault at a time)
Vaults dir is also Syncthing-shared with the Mac, and Claude tmux sessions read/write the same files
```

Key design decisions:

- **One SilverBullet container, one vault at a time.** Tried "point at the parent `~/Vaults` and let SB show all vaults" — SilverBullet's page list is flat, so 1300 markdown files across 9 vaults turned into one ~1300-item list. Per-vault containers give clean per-vault navigation; switching is fast enough that "one at a time" isn't a real cost.
- **Switching is a `docker stop && docker run` with a different `-v` mount.** Encapsulated in `~/bin/sb-switch <vault>` on freeBox. URL stays the same (`https://freebox.<tailnet>.ts.net/`), so the iPhone PWA never has to re-bookmark.
- **HTTPS via Tailscale Serve, not Funnel, not Caddy, not a custom domain.** The `*.ts.net` cert is auto-issued, the endpoint is tailnet-only by default, and no DNS records or port-forwards on the public internet are needed. `tailscale serve` natively supports multiple sub-paths on the same hostname, which is how the launcher coexists with SB at `/launcher`.
- **The launcher is a tiny Python stdlib HTTP server**, not Flask, not Caddy, not a docker container. ~150 lines, no dependencies, runs as a systemd user-mode-style system unit, listed in `freebox-services.md`. It exists *only* to be a phone-friendly switcher — Claude/Mac users would just `ssh freebox sb-switch <vault>` directly.

## Components on freeBox

| Component | Path | Purpose |
|---|---|---|
| Docker container `silverbullet` | `ghcr.io/silverbulletmd/silverbullet:latest` | Serves the current vault on `127.0.0.1:3000`. Restart `unless-stopped`. |
| `~/.silverbullet.env` (mode 600) | local-only | `SB_USER=<user>:<password>` — sourced by `sb-switch`, never tracked in git. Real value in `SECRETS.md`. |
| `~/bin/sb-switch <vault>` | shell script | Stops the current container and starts a new one with `/home/frimann/Vaults/<vault>` bound to `/space`. |
| `~/silverbullet-launcher/launcher.py` | Python (stdlib only) | The vault picker web app. Serves a list of vault buttons; on POST, runs `sb-switch` and re-renders. Source of truth: [`20_scripts/sb-launcher.py`](../20_scripts/sb-launcher.py). |
| `/etc/systemd/system/sb-launcher.service` | systemd unit | Runs `launcher.py` as `frimann` with `SupplementaryGroups=docker` so it can drive Docker. Restart on failure. |
| `tailscale serve` mounts | one-time config | `/` → SB at 3000, `/launcher` → launcher at 3001. Both on `:443`, both tailnet-only. |

## Setup from scratch

Assumes freeBox already has Docker installed (`get.docker.com`), Tailscale running with the operator set to your normal user (`sudo tailscale set --operator=$USER`), and the user is in the `docker` group.

### 1. Pick a password and store it locally

Generate a strong password (`openssl rand -base64 24` is fine), put it in `SECRETS.md` under a `## SilverBullet` section, and write a local-only env file on freeBox:

```bash
ssh freebox 'cat > ~/.silverbullet.env << "EOF"
SB_USER=<your-user>:<your-password>
EOF
chmod 600 ~/.silverbullet.env'
```

`SB_USER` is the only env var that matters in this setup. SilverBullet uses **form-based** authentication, not HTTP Basic — typing the username/password on the SB login screen issues a JWT cookie that persists across browser restarts.

### 2. Install `sb-switch`

```bash
ssh freebox 'mkdir -p ~/bin && cat > ~/bin/sb-switch << "EOF"
#!/usr/bin/env bash
set -euo pipefail

VAULT_NAME="${1:?usage: sb-switch <vault-name>}"
VAULT_PATH="/home/frimann/Vaults/${VAULT_NAME}"

[[ -d "$VAULT_PATH" ]] || { echo "no such vault: $VAULT_PATH" >&2; ls /home/frimann/Vaults/ >&2; exit 1; }

source /home/frimann/.silverbullet.env

docker stop silverbullet 2>/dev/null || true
docker rm   silverbullet 2>/dev/null || true

docker run -d \
    --name silverbullet \
    --restart unless-stopped \
    -p 127.0.0.1:3000:3000 \
    -v "${VAULT_PATH}:/space" \
    -e SB_USER="${SB_USER}" \
    --user 1000:1000 \
    ghcr.io/silverbulletmd/silverbullet:latest > /dev/null

echo "SilverBullet now serving: ${VAULT_NAME}"
EOF
chmod +x ~/bin/sb-switch'
```

Add `~/bin` to PATH if it isn't already (`echo "export PATH=\"\$HOME/bin:\$PATH\"" >> ~/.bashrc`).

Start the first vault:

```bash
ssh freebox 'sb-switch "Workout plan"'
```

### 3. Front it with Tailscale Serve

```bash
sudo tailscale serve --bg --https=443 http://127.0.0.1:3000
tailscale serve status     # should show https://freebox.<tailnet>.ts.net (tailnet only) -> 127.0.0.1:3000
```

Visit `https://freebox.<tailnet>.ts.net` from any browser on the tailnet, log in, and you're in.

### 4. Install the vault launcher

The launcher source lives in [`20_scripts/sb-launcher.py`](../20_scripts/sb-launcher.py). Copy it to freeBox and run the installer (which writes the systemd unit and adds the `/launcher` mount to Tailscale Serve):

```bash
scp 20_scripts/sb-launcher.py freebox:/home/frimann/silverbullet-launcher/launcher.py
./20_scripts/install-sb-launcher.sh
```

`install-sb-launcher.sh` is one-time; for code changes to `sb-launcher.py` afterwards use [`20_scripts/redeploy-sb-launcher.sh`](../20_scripts/redeploy-sb-launcher.sh) which scps the new file and restarts the systemd unit.

After both run, `tailscale serve status` should show two mounts:

```
https://freebox.<tailnet>.ts.net (tailnet only)
|-- /         proxy http://127.0.0.1:3000
|-- /launcher proxy http://127.0.0.1:3001
```

### 5. Install both PWAs on the iPhone

iPhone needs Tailscale installed and signed in (the iOS app handles MagicDNS automatically — no `/etc/resolver` workaround needed).

1. Safari → `https://freebox.<tailnet>.ts.net` → log in → Share → **Add to Home Screen** → "SilverBullet". This is the *editor*.
2. Safari → `https://freebox.<tailnet>.ts.net/launcher` → Share → **Add to Home Screen** → "SB Vaults". This is the *vault picker*.

Two PWA icons on the home screen. The launcher's job is to switch vaults; the SilverBullet PWA's job is to view/edit them.

## Day-to-day usage

### Switching vaults from the iPhone

1. Tap the **SB Vaults** launcher PWA
2. Tap a vault button — the page becomes "Switched to X. SilverBullet is restarting (5–10s)" with an "Open SilverBullet →" button
3. Tap **Open SilverBullet →** (or press home and tap the SB PWA directly)
4. Refresh if needed → you're in the new vault

First switch to a *new* vault triggers a SilverBullet JWT secret regeneration — see the gotcha below. Subsequent switches back to a previously-visited vault reuse the persisted token.

### Switching vaults from the Mac (or any shell)

```bash
ssh freebox 'sb-switch "General vault"'
ssh freebox 'sb-switch "Workout plan"'
ssh freebox 'sb-switch "MAPS 2026 Lecture notes"'
```

You can shell-alias these in `~/.zshrc` if you switch from the Mac frequently:

```bash
alias sb-general='ssh freebox sb-switch "General vault"'
alias sb-workout='ssh freebox sb-switch "Workout plan"'
```

### Inspecting / debugging

```bash
ssh freebox 'docker ps --filter name=silverbullet'
ssh freebox 'docker logs silverbullet --tail 30'
ssh freebox 'docker inspect silverbullet --format "{{range .Mounts}}{{.Source}}{{end}}"'   # which vault?
ssh freebox 'systemctl status sb-launcher'
ssh freebox 'sudo journalctl -u sb-launcher -n 30 --no-pager'
ssh freebox 'tailscale serve status'
```

## Gotchas

### Per-vault first login

SilverBullet generates a **fresh JWT secret per space** (per vault) on the container's first start in that space, persisting it in `<vault>/.silverbullet.auth.json`. Implication:

- The **first time** you switch to a never-visited vault, your existing browser token is invalidated and you have to log in again on the iPhone.
- Subsequent switches back to that vault reuse the persisted secret → no re-login.
- Once you've visited each vault once, switching becomes seamless.

`.silverbullet.auth.json` is in `~/Vaults/.stignore` so it's not synced between Syncthing peers — auth state stays local to freeBox.

If first-login-per-vault becomes annoying: SilverBullet supports a fixed JWT secret via env var (set `SB_AUTH_TOKEN` or similar — check current SB docs); we can stabilize this across all vaults later.

### iOS PWA stays at the wrong URL on relaunch

Without a Web App Manifest, iOS PWAs "remember" the last URL the user navigated to and resume there on the next icon tap. The launcher PWA can therefore get *stuck* showing SilverBullet content if the user taps the "Open SilverBullet →" button (which navigates within the PWA shell).

**Fix is in the launcher already:** the page declares a manifest with `start_url=/launcher` and `scope=/launcher/`, so iOS pins the launcher PWA's home to the vault picker. The "Open SilverBullet →" button uses `target="_blank" rel="noopener"` as a defense-in-depth (iOS' implementation of cross-scope navigation is uneven).

If you ever need to re-add the launcher PWA after editing the manifest, **delete the home screen icon and re-install** — iOS captures the manifest at install time, not at runtime.

### Tailscale Serve strips the path prefix when forwarding

`tailscale serve --set-path=/launcher http://127.0.0.1:3001` forwards `/launcher/anything` to the backend as `/anything` — the backend never sees the `/launcher` prefix. The launcher's HTTP handler accepts both `/switch` and `/launcher/switch` (and likewise `/`, `/launcher`, `/launcher/`) so it works regardless of how it's mounted. If you ever build a similar small web service behind a sub-path, remember to handle this.

### Don't expose SB via Tailscale Funnel

Funnel would put the entire editor behind a single shared `SB_USER` password on the public internet. The blast radius is huge; the convenience over Tailscale Serve is small (Serve already works from any tailnet device, including the iPhone). This is also called out in `freebox-services.md` under "Things deliberately NOT running".

## Reversing the whole thing

If you ever want to back this out:

```bash
# Stop and remove the SilverBullet container
ssh freebox 'docker stop silverbullet && docker rm silverbullet'

# Stop and remove the launcher service
ssh freebox 'sudo systemctl disable --now sb-launcher \
  && sudo rm /etc/systemd/system/sb-launcher.service \
  && sudo systemctl daemon-reload'

# Remove the Tailscale Serve mounts
ssh freebox 'tailscale serve --https=443 --set-path=/launcher off \
  && tailscale serve --https=443 off'

# Optional: remove the launcher source and the env file
ssh freebox 'rm -rf ~/silverbullet-launcher ~/.silverbullet.env ~/bin/sb-switch'
```

Vaults under `~/Vaults/` are untouched by any of the above — they're just files Syncthing manages, independent of SilverBullet.
