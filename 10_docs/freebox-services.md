# freeBox services

What's currently running on freeBox beyond the OS basics. Each service entry says how it's installed, where its config lives, what it listens on, and how it's reachable.

## Syncthing — vault sync

- **Service:** `syncthing@frimann.service` (system unit from the Ubuntu `syncthing` package, instantiated for the `frimann` user). Enabled, starts at boot.
- **Ports:**
  - `127.0.0.1:8384` — Web GUI, loopback only. Exposed via Tailscale Serve at `https://freebox.<tailnet>.ts.net:8384` (tailnet only). Requires `<insecureSkipHostcheck>true</insecureSkipHostcheck>` in the `<gui>` block of `~/.local/state/syncthing/config.xml` — without it Syncthing rejects requests where the Host header isn't `localhost` (safe here because access is already gated by Tailscale). Fallback: SSH tunnel `ssh -L 8384:127.0.0.1:8384 freebox` then http://localhost:8384.
  - `:22000` (TCP/UDP) — Syncthing protocol, used for peer connections (Tailscale-routed in practice).
- **Folder shared:** `~/Vaults/`, mode `sendreceive`, paired peer-to-peer with the Mac (and any other Syncthing peer on the tailnet). Syncthing's own discovery handles the connection.
- **`.stignore` gotcha:** Syncthing refuses to delete a directory on a peer if that directory still contains files matched by `.stignore`. Volatile patterns like `.DS_Store`, `.obsidian/workspace*`, `.obsidian/cache`, etc. **must** use the `(?d)` prefix so Syncthing is allowed to remove them on delete. Symptom is `needDeletes > 0` and `pullErrors > 0` stuck on the peer that's behind. See `10_docs/obsidian-sync.md` for the full decision block.

## SilverBullet — web-based markdown editor for vaults

Full setup, day-to-day usage, and troubleshooting in [`silverbullet.md`](silverbullet.md). The summary here is just "what is running and where".

- **Service:** Docker container `silverbullet`, image `ghcr.io/silverbulletmd/silverbullet:latest`, restart policy `unless-stopped`. No systemd unit — Docker brings it back at boot via `docker.service`.
- **Listens on:** `127.0.0.1:3000` (loopback only — not directly reachable from the public internet).
- **Vault mounted in container:** one of `~/Vaults/<vault>/` bound to `/space`. **Only one vault at a time** — switching is done by stopping the container and starting a new one with a different `-v` mount, encapsulated in `~/bin/sb-switch <vault>`. Container name (`silverbullet`), host port (`3000`), and HTTPS URL all stay the same across switches.
- **Auth:** form-based login (not HTTP Basic) via `SB_USER=<user>:<password>` env var. The actual value lives in `~/.silverbullet.env` (mode 600) on freeBox and in `SECRETS.md` locally — never committed. SilverBullet generates a fresh JWT secret per space on first start, persisted in `<vault>/.silverbullet.auth.json` (which is `(?d)`-ignored by Syncthing — auth state stays local to freeBox).
- **Container env actually in use:** just `SB_USER`. SilverBullet picks up the listen address (`0.0.0.0`), port (`3000`), and space dir (`/space`) from defaults; no `SB_HOSTNAME`/`SB_FOLDER`/`SB_PORT` env vars are set.
- **Inspecting:** `docker ps`, `docker logs silverbullet`, `docker inspect silverbullet --format "{{range .Mounts}}{{.Source}}{{end}}"` (the last one tells you which vault is currently mounted).

## sb-launcher — vault picker web app for the iPhone

- **Service:** `sb-launcher.service` — a system-mode systemd unit running `python3 /home/frimann/silverbullet-launcher/launcher.py` as the `frimann` user with `SupplementaryGroups=docker` so it can drive the Docker daemon. Restart on failure, enabled at boot.
- **Listens on:** `127.0.0.1:3001` (loopback only). Reachable from the tailnet because Tailscale Serve mounts it at `https://freebox.<tailnet>.ts.net/launcher`.
- **What it does:** serves a single HTML page listing every non-hidden subdirectory of `~/Vaults/` as a button. POSTing a vault name runs `~/bin/sb-switch <vault>`, which restarts the SilverBullet container with that vault mounted, and re-renders the page with a "Switched" banner. No state of its own — vault list comes from the live filesystem on every request.
- **Source of truth:** [`20_scripts/sb-launcher.py`](../20_scripts/sb-launcher.py). Stdlib only, no dependencies. Edit there, then run [`20_scripts/redeploy-sb-launcher.sh`](../20_scripts/redeploy-sb-launcher.sh) from the Mac to scp + restart.
- **First-time install:** [`20_scripts/install-sb-launcher.sh`](../20_scripts/install-sb-launcher.sh) — writes the systemd unit, enables it, and adds the `/launcher` Tailscale Serve mount.
- **Why a separate launcher rather than just SSHing `sb-switch` from a phone shortcut:** lets the iPhone be the only device involved (no SSH credentials in iOS Shortcuts), the vault list updates automatically when vaults are added/removed on disk, and the only thing the public-facing endpoint can do is `sb-switch` (validated against the live filesystem listing — no path traversal or arbitrary command execution).

## Tailscale — VPN and HTTPS front for SilverBullet + launcher

- **Tailscale itself:** running, the freeBox node has a stable tailnet IP (in `SECRETS.md`). The user is set as the tailscale operator (`sudo tailscale set --operator=$USER`) so most `tailscale ...` commands don't need sudo.
- **Tailscale Serve:** three mounts, all tailnet-only (not Funnel — not the public internet):
  ```
  https://freebox.<tailnet>.ts.net (tailnet only)
  |-- /         proxy http://127.0.0.1:3000   ← SilverBullet
  |-- /launcher proxy http://127.0.0.1:3001   ← sb-launcher

  https://freebox.<tailnet>.ts.net:8384 (tailnet only)
  |-- /         proxy http://127.0.0.1:8384   ← Syncthing Web GUI
  ```
  The certs are auto-issued by Let's Encrypt via Tailscale and renew automatically.
- **Verifying:** `tailscale serve status` (no sudo needed with operator set).
- **Recreating from scratch** (after a wipe or `tailscale serve --https=443 off`):
  ```bash
  sudo tailscale serve --bg --https=443 http://127.0.0.1:3000
  sudo tailscale serve --bg --https=443 --set-path=/launcher http://127.0.0.1:3001
  sudo tailscale serve --bg --https=8384 http://127.0.0.1:8384
  ```
  Note: `tailscale serve --set-path=/launcher` **strips the `/launcher` prefix** before forwarding to the backend, so the launcher's HTTP handler is written to accept both `/foo` and `/launcher/foo` for every route.
- **Why no Funnel:** SB's single shared `SB_USER` credential is the only protection in front of the editor; exposing it to the public internet would be a much bigger blast radius for a single shared password. Tailscale Serve already works from any tailnet device, including the iPhone (with the iOS Tailscale app installed and signed in).

## Claude Code Remote Control — one tmux session per vault

- **Script:** [`20_scripts/freebox-vaults-up.sh`](../20_scripts/freebox-vaults-up.sh).
- **Auto-start:** [`20_scripts/freebox-vaults-up.service`](../20_scripts/freebox-vaults-up.service) — a systemd **user** unit installed at `~/.config/systemd/user/freebox-vaults-up.service`.
- **Behavior:** the script scans `~/Vaults/*/`, pre-populates `hasTrustDialogAccepted: true` in `~/.claude.json` for each vault dir (otherwise `claude remote-control` exits immediately on the workspace-trust check), then starts one detached tmux session per vault running:
  ```
  claude remote-control --name "freebox-<sanitized-vault>"
  ```
  where the sanitized name is the vault dir basename, transliterated to ASCII (`Björn` → `Bjorn`) via GNU iconv, lowercased, and with non-alphanumeric runs collapsed to `_`. Session names are `vault-<sanitized>`. Idempotent: re-running picks up new vaults without disturbing existing sessions.
- **Linger requirement:** systemd **user** units don't run at boot unless lingering is enabled for the user. One-time:
  ```bash
  sudo loginctl enable-linger frimann
  ```
- **Install / update on the server:**
  ```bash
  ssh freebox
  cd ~/freeBox && git pull
  mkdir -p ~/.config/systemd/user
  cp 20_scripts/freebox-vaults-up.service ~/.config/systemd/user/
  systemctl --user daemon-reload
  systemctl --user enable --now freebox-vaults-up.service
  ```
- **Auto-detect new vaults:** [`20_scripts/freebox-vaults-watch.path`](../20_scripts/freebox-vaults-watch.path) + [`freebox-vaults-watch.service`](../20_scripts/freebox-vaults-watch.service) — a systemd **user** path unit that watches `~/Vaults/` for changes (new subdirectory created, directory renamed, etc.) and re-runs `freebox-vaults-up.sh` automatically. No manual re-run needed after adding a vault.
- **Install the watcher (one-time, on the server):**
  ```bash
  cp 20_scripts/freebox-vaults-watch.{path,service} ~/.config/systemd/user/
  systemctl --user daemon-reload
  systemctl --user enable --now freebox-vaults-watch.path
  ```
- **Manual run:** `bash ~/freeBox/20_scripts/freebox-vaults-up.sh`
- **Inspect a session:** `tmux attach -t vault-<sanitized>` (Ctrl-b d to detach without killing).

## Things deliberately NOT running on freeBox

Recorded so they don't get accidentally re-added.

- **Obsidian itself.** No headless build exists. Vaults on freeBox are edited via Claude or SilverBullet, not Obsidian. Obsidian on the Mac and iPhone is the editor.
- **Obsidian Sync (the paid service).** It can't run headlessly on Linux. Cross-device sync is Syncthing's job here.
- **Tailscale Funnel.** SilverBullet is reachable over Tailscale Serve only (tailnet-internal). Exposing it to the public internet would put the single shared `SB_USER` basic-auth credential in a much bigger blast radius.
