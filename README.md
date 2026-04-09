# freeBox

Setup and maintenance for **freeBox**, a Linode Ubuntu 24.04 VPS used as a remote Claude Code / terminal workstation.

## Purpose

- A stable place to run Claude Code in `tmux`
- Reachable from Mac and iPhone via SSH and Tailscale
- Claude Remote Control friendly (long-running session on the box)
- Obsidian Sync remains the planning/notes layer; this repo is the executable layer

## Layout

```
freeBox/
├── README.md              ← this file (human overview)
├── CLAUDE.md              ← Claude Code project instructions
├── TODO.md                ← persistent server-setup checklist
├── .gitignore
├── 10_docs/
│   ├── setup.md             ← end-to-end runbook for the server
│   ├── obsidian-sync.md     ← vault sync decision (Syncthing, decided 2026-04-09)
│   ├── freebox-services.md  ← what's running on freeBox: Syncthing, SilverBullet, Tailscale Serve, vault sessions
│   ├── mac-workstation.md   ← runbook for the Mac always-on workstation experiment
│   └── linode-vs-mac-mini.md
├── 20_scripts/
│   ├── bootstrap.sh                  ← idempotent first-time provisioning of freeBox
│   ├── check-health.sh               ← quick health snapshot
│   ├── freebox-vaults-up.sh          ← start one Claude remote-control tmux session per vault
│   ├── freebox-vaults-up.service     ← systemd user unit that runs the above at boot
│   └── mac-workstation-up.sh         ← bring Mac sessions and Obsidian windows back up
└── 00_inbox/              ← local-only scratch area (gitignored)
    └── files from chatGPT/  ← original ChatGPT proposals, kept as reference
```

Numbered prefixes sort folders in reading order. The unprefixed root files (`README.md`, `CLAUDE.md`, `TODO.md`, `.gitignore`) keep their conventional names so tool integrations (Claude Code auto-load, GitHub README rendering, git) keep working.

> **This repository is public.** Sensitive values (server IPs, usernames, keys) live in `SECRETS.md`, which is gitignored and never committed. See `CLAUDE.md` for the full rule.

## Quick start

1. `ssh freebox`
2. Copy `20_scripts/bootstrap.sh` to the server and run it with `sudo`
3. `sudo tailscale up` and complete browser auth
4. `tmux new -s claude && claude`

Full details in [`10_docs/setup.md`](10_docs/setup.md).

## Conventions

- Daily work as the normal user, not root
- `sudo` only when needed
- Claude runs inside `tmux` so sessions survive disconnects
- Never disable a working access path before verifying the replacement
- Planning and decision logs live in Obsidian, not here
