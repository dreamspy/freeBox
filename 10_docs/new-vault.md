# Adding a new vault

Step-by-step checklist for adding a new Obsidian vault to the sync mesh and Claude sessions across all machines.

## Machines

| Name          | Sync mechanism        | Vault path       |
| ------------- | --------------------- | ---------------- |
| **freeBox**   | Syncthing             | `~/Vaults/<name>/` |
| **freeMac**   | Syncthing + Obsidian Sync | `~/Vaults/<name>/` |
| **atom**      | Syncthing + Obsidian Sync | `~/Vaults/<name>/` |
| **freePhone** | Obsidian Sync         | (managed by Obsidian app) |

## Steps

### 1. Create the vault in Obsidian (any device)

Open Obsidian on any device that has Obsidian Sync enabled (atom, freeMac, or freePhone). Create the vault and enable Sync for it. This makes it available in the Obsidian Sync cloud.

### 2. Pull the vault on each Mac via Obsidian Sync

On **freeMac** and **atom** (skip whichever you created it on):

1. Open Obsidian
2. Vault picker → **"Show vaults stored in Obsidian Sync"**
3. Pick the new vault → set the local destination to `~/Vaults/<name>`
4. Wait for the initial sync to complete

> This is the one unavoidable manual GUI step per Mac. Obsidian Sync has no CLI and no "sync all vaults" option.

### 3. Syncthing picks it up automatically

Syncthing shares `~/Vaults/` as a whole, so the new subdirectory propagates to all Syncthing peers (freeBox, freeMac, atom) without any configuration. Verify:

- Check the Syncthing GUI on freeBox (`https://freebox.<tailnet>.ts.net:8384` or `ssh -L 8384:127.0.0.1:8384 freebox`) — the folder should show the new vault syncing.
- On freeBox: `ls ~/Vaults/<name>/` — files should be arriving.

### 4. Claude sessions pick it up automatically

Both `freebox-vaults-up.sh` and `mac-workstation-up.sh` scan `~/Vaults/` for subdirectories. The next time they run (or on the next reboot), they'll create a tmux session for the new vault.

To pick it up immediately without waiting:

```bash
# On freeBox:
ssh freebox 'bash ~/Vaults/freeBox/20_scripts/freebox-vaults-up.sh'

# On freeMac:
ssh freemac 'bash ~/Vaults/freeBox/20_scripts/mac-workstation-up.sh'
```

The systemd path watcher on freeBox (`freebox-vaults-watch.path`) also triggers automatically when `~/Vaults/` changes.

### 5. SilverBullet (optional)

SilverBullet on freeBox serves one vault at a time. The new vault is already available — just switch to it when you want to edit it from freePhone:

```bash
ssh freebox sb-switch <name>
```

Or use the launcher PWA on freePhone — the new vault will appear in the list automatically.

## Verification

- [ ] `ls ~/Vaults/<name>/` shows files on freeBox, freeMac, and atom
- [ ] Edit a note on freePhone → appears on all other machines within a minute
- [ ] `tmux ls` on freeBox and freeMac shows a session for the new vault
- [ ] (Optional) SilverBullet can switch to the new vault: `sb-switch <name>`
