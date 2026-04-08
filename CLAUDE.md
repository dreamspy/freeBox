# CLAUDE.md

## Project purpose

This project sets up and maintains **freeBox**, a Linode Ubuntu 24.04 LTS VPS used as a remote Claude Code / terminal workstation. The server is reached via SSH and Tailscale, and Claude is expected to run inside `tmux` so sessions survive disconnects.

## Environment

- Target OS: Ubuntu 24.04 LTS (x86_64)
- Host: Linode shared CPU
- Public IP: see `SECRETS.md` (local only, gitignored)
- SSH alias: `ssh freeBox` (defined in `~/.ssh/config`, logs in as a sudo user — exact username in `SECRETS.md`)
- Primary access paths: SSH, Tailscale (once installed)
- Obsidian Sync remains the main vault sync layer

## Working style

- Prefer safe, minimal, reversible changes
- Explain risky commands before suggesting them
- Keep commands compatible with Ubuntu 24.04 LTS
- When changing setup steps, update `10_docs/setup.md` to match
- Do not make unrelated changes
- Be concrete: copy-pasteable command blocks, no fluff

## Operational rules

- Daily work happens as the normal user, not root
- Use `sudo` only when needed; do not assume direct root SSH is enabled
- **Never disable a working access path before verifying the replacement works** (especially: don't tighten SSH or enable a firewall without confirming the new path first)
- Prefer `tmux` for any long-running Claude session
- Prefer Tailscale-aware guidance once Tailscale is set up

## Repo conventions

- `README.md` — human overview (root, conventional name)
- `CLAUDE.md` — this file, Claude-facing instructions (root, conventional name)
- `10_docs/` — durable documentation
- `20_scripts/` — executable scripts
- `files from chatGPT/` — original ChatGPT proposal bundle, kept as reference; **do not edit**
- Numbered prefixes (`10_`, `20_`) sort folders by reading order; new items use gaps so insertions are easy

## Cautions

- Do not assume `npm install -g` works without sudo or permission handling
- Do not enable `ufw` without first allowing OpenSSH on the same invocation
- Do not commit secrets: SSH private keys, Tailscale auth keys, API keys, `.env` files
- Keep this machine separate from more sensitive workloads
