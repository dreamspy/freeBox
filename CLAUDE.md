# CLAUDE.md

## ⚠ THIS REPO IS PUBLIC ⚠

This repository is published at **`github.com/dreamspy/freeBox`** as a **public** GitHub repo. Anything committed to a tracked file is visible to the entire internet, indexed by search engines, and effectively permanent (force-pushing does not erase history that has been mirrored or scraped).

**Hard rule — never commit anything that could be exploited if a hostile reader saw it.** This includes, but is not limited to:

- Server IPs, hostnames, or DNS names that resolve to real machines you own
- Usernames used for SSH or any other login
- Tailscale auth keys, pre-auth keys, machine keys, or tailnet IPs (the 100.x range)
- SSH private keys, passphrases, or `authorized_keys` contents
- API keys, tokens, OAuth secrets, session cookies, JWTs (Anthropic, GitHub, cloud providers, anything)
- Passwords, password hashes, recovery codes, 2FA seeds
- `.env` files, credential files, certificates (`*.pem`, `*.key`, `*.crt`, `*.p12`, `*.pfx`)
- Internal URLs, webhook URLs with tokens in the path or query string
- Customer data, personal data, private email content
- File contents from `SECRETS.md`, `00_inbox/`, or `.obsidian/` (all gitignored — keep them that way)

**Where sensitive values live instead:** `SECRETS.md` at the project root. It is gitignored and exists only on the local machine. When new sensitive values appear (Tailscale keys, API keys, etc.), add them to `SECRETS.md`, not to any tracked file.

**Before any `git add`, `git commit`, or `git push`:**

1. Run `git status` and `git diff --staged` and read what is actually staged.
2. If anything in the staged content matches the categories above, stop and move it to `SECRETS.md` first.
3. Public files should reference sensitive values only by placeholder (`<server-ip>`, `<your-user>`) with a note pointing to `SECRETS.md`.
4. When in doubt, ask the user before committing — a wrong commit on a public repo is hard to undo.

**If you suspect a leak has already happened:** tell the user immediately. Do not try to "fix" it by force-pushing alone — rotation of the leaked credential is the only real fix.

## Project purpose

This project sets up and maintains **freeBox**, a Linode Ubuntu 24.04 LTS VPS used as a remote Claude Code / terminal workstation. The server is reached via SSH and Tailscale, and Claude is expected to run inside `tmux` so sessions survive disconnects.

## Environment

- Target OS: Ubuntu 24.04 LTS (x86_64)
- Host: Linode shared CPU
- Public IP: see `SECRETS.md` (local only, gitignored)
- SSH alias: `ssh freebox` (defined in `~/.ssh/config`, logs in as a sudo user — exact username in `SECRETS.md`)
- Primary access paths: SSH, Tailscale (active — Tailscale IP in `SECRETS.md`)
- Vaults live on freeBox at `~/Vaults/<vault>/` and are kept in sync with the Mac (and any other peer) via **Syncthing** over Tailscale — see `10_docs/obsidian-sync.md` (decided 2026-04-09) and `10_docs/freebox-services.md` for the running services

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
- `TODO.md` — persistent server-setup checklist; update it when work is finished or new items appear
- `SECRETS.md` — local-only, gitignored; the only place sensitive values may live
- `10_docs/` — durable documentation
  - `setup.md` — end-to-end runbook
  - `obsidian-sync.md` — comparison of vault-sync options (undecided)
- `20_scripts/` — executable scripts (`bootstrap.sh`, `check-health.sh`)
- `00_inbox/` — local-only scratch area, gitignored; contains `files from chatGPT/` (the original ChatGPT proposal bundle, kept as reference — **do not edit**)
- `.obsidian/` — local Obsidian vault config, gitignored
- Numbered prefixes (`10_`, `20_`) sort folders by reading order; new items use gaps so insertions are easy
- Three files keep conventional unprefixed names so tool integrations work: `README.md` (GitHub), `CLAUDE.md` (Claude Code auto-load), `.gitignore` (git)

## Cautions

- Do not assume `npm install -g` works without sudo or permission handling
- Do not enable `ufw` without first allowing OpenSSH on the same invocation
- Keep this machine separate from more sensitive workloads
- See the **THIS REPO IS PUBLIC** section at the top for the full secret-handling rule
