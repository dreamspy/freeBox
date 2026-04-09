# freeBox services

What's currently running on freeBox beyond the OS basics. Each service entry says how it's installed, where its config lives, what it listens on, and how it's reachable.

## Syncthing — vault sync

- **Service:** `syncthing@frimann.service` (system unit from the Ubuntu `syncthing` package, instantiated for the `frimann` user). Enabled, starts at boot.
- **Ports:**
  - `127.0.0.1:8384` — Web GUI, loopback only. Reach it from the Mac via an SSH tunnel: `ssh -L 8384:127.0.0.1:8384 freebox` then http://localhost:8384.
  - `:22000` (TCP/UDP) — Syncthing protocol, used for peer connections (Tailscale-routed in practice).
- **Folder shared:** `~/Vaults/`, mode `sendreceive`, paired peer-to-peer with the Mac (and any other Syncthing peer on the tailnet). Syncthing's own discovery handles the connection.
- **`.stignore` gotcha:** Syncthing refuses to delete a directory on a peer if that directory still contains files matched by `.stignore`. Volatile patterns like `.DS_Store`, `.obsidian/workspace*`, `.obsidian/cache`, etc. **must** use the `(?d)` prefix so Syncthing is allowed to remove them on delete. Symptom is `needDeletes > 0` and `pullErrors > 0` stuck on the peer that's behind. See `10_docs/obsidian-sync.md` for the full decision block.

## SilverBullet — web-based markdown editor for vaults

- **Service:** Docker container `silverbullet`, image `ghcr.io/silverbulletmd/silverbullet:latest`, restart policy `unless-stopped`. There is **no separate systemd unit** — Docker brings it back at boot via `docker.service`.
- **Listens on:** `127.0.0.1:3000` (loopback only — not directly reachable from the public internet).
- **Vault mounted in container:** `~/Vaults/Workout plan` → `/space`. Currently one vault; mount more under different container paths if needed.
- **Auth:** HTTP basic auth via `SB_USER=<user>:<password>` env var. The actual value lives in `SECRETS.md` — never commit it.
- **Container env (sensitive bits replaced):**
  ```
  SB_USER=<user>:<password-from-SECRETS.md>
  SB_HOSTNAME=0.0.0.0
  SB_FOLDER=/space
  SB_PORT=3000
  ```
- **Inspecting:** `docker ps`, `docker logs silverbullet`, `docker inspect silverbullet`.

## Tailscale — VPN and HTTPS front for SilverBullet

- **Tailscale itself:** running, the freeBox node has a stable tailnet IP (in `SECRETS.md`).
- **Tailscale Serve:** port `:443` is listening on the tailnet IPv4 and IPv6 addresses. This is consistent with Tailscale Serve fronting SilverBullet's `127.0.0.1:3000` and exposing it as `https://freebox.<tailnet>.ts.net/` over the tailnet only (not Funnel — not the public internet).
- **Verifying / restoring the config:** reading the live serve config requires root.
  ```bash
  ssh freebox sudo tailscale serve status
  ```
  If it's missing, recreate with something like:
  ```bash
  sudo tailscale serve --bg --https=443 --set-path / http://127.0.0.1:3000
  ```
  (Adjust to match the existing setup before applying.)
- **Why no Funnel:** the SilverBullet `SB_USER` basic-auth credential is the only protection in front of the editor; exposing it to the public internet via Funnel would be a much bigger blast radius for a single shared password.

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
- **Manual run:** `bash ~/freeBox/20_scripts/freebox-vaults-up.sh`
- **Inspect a session:** `tmux attach -t vault-<sanitized>` (Ctrl-b d to detach without killing).

## Things deliberately NOT running on freeBox

Recorded so they don't get accidentally re-added.

- **Obsidian itself.** No headless build exists. Vaults on freeBox are edited via Claude or SilverBullet, not Obsidian. Obsidian on the Mac and iPhone is the editor.
- **Obsidian Sync (the paid service).** It can't run headlessly on Linux. Cross-device sync is Syncthing's job here.
- **Tailscale Funnel.** SilverBullet is reachable over Tailscale Serve only (tailnet-internal). Exposing it to the public internet would put the single shared `SB_USER` basic-auth credential in a much bigger blast radius.
