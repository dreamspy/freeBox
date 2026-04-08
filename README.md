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
├── README.md           ← this file (human overview)
├── CLAUDE.md           ← Claude Code project instructions
├── .gitignore
├── 10_docs/
│   └── setup.md        ← end-to-end runbook for the server
├── 20_scripts/
│   ├── bootstrap.sh    ← idempotent first-time provisioning
│   └── check-health.sh ← quick health snapshot
└── files from chatGPT/ ← original ChatGPT proposals, kept as source of truth
```

Numbered prefixes sort folders and files in reading order. The three exceptions (`README.md`, `CLAUDE.md`, `.gitignore`) keep their conventional names so tool integrations (Claude Code auto-load, GitHub README rendering, git) keep working.

## Quick start

1. `ssh freeBox`
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
