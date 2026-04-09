# freeBox setup runbook

End-to-end provisioning for freeBox (Linode, Ubuntu 24.04 LTS).

Goal: a reliable server that runs Claude Code in `tmux`, reachable from Mac and iPhone over SSH and Tailscale, with sane defaults and a clear recovery path.

---

## 0. Assumptions

- Server alias `freebox` resolves via `~/.ssh/config`
- Normal user is a sudo user (exact username in `SECRETS.md`, kept out of the public repo)
- You are SSH-ing in from a machine where key auth already works

---

## 1. First connect and reboot

```bash
ssh freebox
sudo reboot
```

Reconnect:

```bash
ssh freebox
```

---

## 2. Update packages

```bash
sudo apt update && sudo apt upgrade -y
```

---

## 3. Install base tools

```bash
sudo apt install -y tmux git curl wget unzip ripgrep fd-find zsh htop build-essential ufw
```

What they're for:

| tool | purpose |
|---|---|
| `tmux` | persistent terminal sessions |
| `git` | repos |
| `curl`, `wget` | downloads |
| `unzip` | archives |
| `ripgrep`, `fd-find` | fast search |
| `zsh` | optional nicer shell |
| `htop` | resource view |
| `build-essential` | compile deps |
| `ufw` | firewall |

---

## 4. Set timezone

```bash
sudo timedatectl set-timezone Atlantic/Reykjavik
timedatectl
```

---

## 5. Install Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

`sudo tailscale up` prints a `https://login.tailscale.com/a/...` URL. Open it in a browser, log in, and the machine joins your tailnet.

Verify:

```bash
tailscale ip -4
tailscale status
```

Optional: enable Tailscale SSH so you don't manage SSH keys for the private path:

```bash
sudo tailscale up --ssh
```

Optional: disable key expiry on this server in the [Tailscale admin console](https://login.tailscale.com/admin/machines) so it doesn't log out after 180 days.

---

## 6. Install Claude Code

Preferred installer:

```bash
curl -fsSL https://claude.ai/install.sh | bash
claude --version
```

Fallback if the installer ever fails:

```bash
sudo npm install -g @anthropic-ai/claude-code
claude --version
```

The plain `npm install -g` (without sudo) will fail with `EACCES` because it tries to write into `/usr/lib/node_modules`. Use sudo or the official installer.

---

## 7. Start Claude inside tmux

```bash
tmux new -s claude
```

Inside tmux:

```bash
 
```

Detach without killing the session: `Ctrl-b` then `d`.

Reattach later:

```bash
tmux attach -t claude
```

List sessions:

```bash
tmux ls
```

Why tmux: Claude Remote Control connects to a *running* Claude session. If the session dies (network drop, terminal close), Remote Control dies with it. tmux keeps the session alive across disconnects.

---

## 8. Enable Remote Control when wanted

From a shell:

```bash
claude remote-control
```

Or from inside Claude: `/remote-control`. Follow the URL/QR flow.

---

## 9. Working folder

```bash
mkdir -p ~/work
cd ~/work
```

Clone repos here.

---

## 10. Firewall

**Important:** allow SSH *before* enabling the firewall. The order below is safe.

```bash
sudo ufw allow OpenSSH
sudo ufw enable
sudo ufw status verbose
```

If you've changed the SSH port, allow that port specifically instead of `OpenSSH`.

---

## 11. Optional SSH hardening

**Only do this after you have confirmed all of:**

- Normal-user SSH login works
- Key-based login works (no password prompt)
- Tailscale access works, if you intend to rely on it as a fallback

Edit:

```bash
sudo nano /etc/ssh/sshd_config
```

Recommended values:

```text
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```

Apply:

```bash
sudo systemctl restart ssh
```

If `PermitRootLogin no` is set, you still get root via:

```bash
sudo -i
```

---

## 12. Optional: zsh as default shell

```bash
chsh -s $(which zsh)
```

Log out and back in.

---

## 13. Validation checklist

After all the above, these should all work:

```bash
claude --version            # Claude installed
tailscale status            # Tailscale up and authenticated
tmux ls                     # at least one Claude session
sudo systemctl status ssh   # SSH active
sudo ufw status verbose     # firewall on, OpenSSH allowed
```

And from another machine: `ssh freebox` still works, and `ssh <your-user>@<tailscale-ip>` works.

---

## 13b. Mac client gotcha — MagicDNS with Homebrew `tailscaled`

If your Mac is running the **Homebrew** build of Tailscale (`/opt/homebrew/bin/tailscaled`) rather than the App Store / official Mac app, MagicDNS hostnames like `freebox.<tailnet>.ts.net` will **not resolve via the system resolver** even when:

- MagicDNS is enabled in the tailnet admin console
- `tailscale debug prefs` shows `"CorpDNS": true`
- `tailscale status` shows the peer node correctly

The Homebrew daemon doesn't install the per-domain DNS resolver that macOS uses to route a specific suffix to a specific nameserver. Symptom: `dig` returns nothing for the FQDN, but querying Tailscale's resolver directly works (`dig @100.100.100.100 freebox.<tailnet>.ts.net` returns the 100.x IP just fine).

**Fix (one-liner, fully reversible):**

```bash
sudo mkdir -p /etc/resolver \
  && echo "nameserver 100.100.100.100" | sudo tee /etc/resolver/<tailnet>.ts.net \
  && sudo killall -HUP mDNSResponder
```

Replace `<tailnet>.ts.net` with your actual tailnet MagicDNS suffix (in `SECRETS.md`). After this, `curl https://freebox.<tailnet>.ts.net/` and Safari both resolve correctly. (`dig` will *still* show empty — `dig` bypasses `/etc/resolver/`. Test with `curl` or a browser, not `dig`.)

To undo: `sudo rm /etc/resolver/<tailnet>.ts.net`.

The official Mac App Store / standalone Tailscale app handles this automatically via a system network extension and doesn't need the workaround. The Homebrew CLI build is fine for everything else (`tailscale up`, `tailscale status`, `tailscale serve`), it just can't install per-domain resolvers on macOS.

iOS Tailscale uses the iOS network extension and handles MagicDNS correctly out of the box — no equivalent workaround needed there.

---

## 14. Common failures

**`ssh: connection refused`** — SSH service down, firewall blocking 22, or wrong port. Check `sudo systemctl status ssh` and `sudo ufw status verbose`.

**`Permission denied (publickey)`** — wrong key, missing entry in `~/.ssh/authorized_keys`, or wrong permissions. `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`.

**`npm EACCES`** — see step 6, use sudo or the official installer.

**`claude: command not found`** — installer didn't finish, or PATH not refreshed. Re-run installer, then `which claude`.

**Tailscale installed but not connected** — `sudo tailscale up` and complete the browser auth.

**Remote Control not responding** — Claude process died or tmux session disappeared. `tmux ls`, then `tmux attach -t claude` or start a new one.

---

## 15. Day-to-day cheat sheet

```bash
ssh freebox                       # connect
tmux attach -t claude             # reattach
# work in Claude
# Ctrl-b d to detach
sudo apt update && sudo apt upgrade -y   # keep current
```

Health snapshot:

```bash
bash 20_scripts/check-health.sh
```

---

## 16. SilverBullet on freeBox (iOS-friendly markdown editor)

A separate runbook covers the SilverBullet container, the per-vault `sb-switch` workflow, and the Python-based vault launcher PWA: see [`silverbullet.md`](silverbullet.md). The "what services are running" view is in [`freebox-services.md`](freebox-services.md).

The short version of how to use it once installed:

- `https://freebox.<tailnet>.ts.net` — SilverBullet, currently mounted vault. Add to iPhone home screen as a PWA.
- `https://freebox.<tailnet>.ts.net/launcher` — vault picker. Tap a vault → 5–10s wait → SilverBullet container is restarted with that vault mounted. Also a PWA on the iPhone home screen.
- `ssh freebox sb-switch "Vault Name"` — same thing from a shell.

Both URLs are tailnet-only via Tailscale Serve (no Funnel, no public DNS, no Caddy).
