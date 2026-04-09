# Obsidian sync options for freeBox

How to share Obsidian vaults between freeBox, Mac, and iPhone so Claude on the server can edit them.

> **Status: decided, 2026-04-09 — Syncthing-based (Option A variant).**
>
> Vaults **do live on freeBox**, in `~/Vaults/`, and are kept in sync with the Mac (and any other peer) via **Syncthing**. The Vaults folder is shared as `sendreceive` between Mac and freeBox over Tailscale; Syncthing's own discovery handles the connection (port `22000`, GUI on `127.0.0.1:8384`). This supersedes the earlier 2026-04-08 "vaults off freeBox" decision.
>
> **Why the reversal:** keeping vaults on freeBox is a hard requirement so Claude on the server can read and edit them directly without going through Remote Control round-trips, and so vault content is available on a host that's reachable independently of the Mac.
>
> **`.stignore` gotcha (learned the hard way):** Syncthing will refuse to delete a directory on a peer if that directory still contains files matched by `.stignore` — pull errors look like `delete dir: directory has been deleted on a remote device but contains ignored files (see ignore documentation for (?d) prefix)`. Any volatile/local-only pattern that can legitimately be left behind in a directory you might later delete (Obsidian's `.obsidian/workspace*`, `.obsidian/cache`, macOS's `.DS_Store`/`._*`, etc.) **must** be prefixed with `(?d)` so Syncthing is allowed to remove it on delete. Conflict files (`.sync-conflict-*`) already use `(?d)`; everything else volatile should too. If you see "needDeletes > 0" stuck on a peer, this is almost always why — check `~/Vaults/.stignore` on the peer that's stuck.
>
> The full comparison below is preserved as background — it's the research that fed both the original (Option G) and the current (Syncthing) decisions.

## Constraints to know first

- **Obsidian Sync (the paid service) cannot run on a headless Linux server.** It only works through the Obsidian desktop/mobile app — no CLI, no daemon, no API. So if Obsidian Sync is in the chain, *something running Obsidian* has to bridge the server to it.
- **Obsidian itself does not need to run on the server.** Vaults are plain markdown; Claude reads and edits them without Obsidian present anywhere.
- iPhone Obsidian can open vaults from: iCloud Drive, Obsidian Sync, or any local folder under "On my iPhone" / Files. **iCloud Drive is not reachable from a Linux server**, so it's not a useful path here.

---

## Option A — Mac as the bridge (uses Obsidian Sync)

```
[ freeBox vault ] ⇄ Syncthing ⇄ [ Mac vault ] ⇄ Obsidian Sync ⇄ [ iPhone vault ]
                                      ↑
                                Mac runs Obsidian
```

- Mac holds the canonical vault for Obsidian Sync purposes.
- Obsidian Sync handles Mac ↔ iPhone as it does today.
- A second sync layer (Syncthing is cleanest; rsync over Tailscale also works) keeps Mac ↔ freeBox in sync.
- Claude on freeBox edits → Syncthing pushes to Mac → Obsidian on Mac sees it → Obsidian Sync pushes to iPhone.

**Pros:** existing Obsidian Sync workflow stays intact; iPhone side needs zero changes.
**Cons:** Mac must be running (and Obsidian open or at least logged in) for changes to flow end-to-end. If the Mac is off, server edits don't reach the phone until it wakes.

---

## Mac-less options

### Option B — Syncthing + Möbius Sync (peer-to-peer, no central service)

```
[ freeBox ] ⇄ Syncthing ⇄ [ iPhone ] (Möbius Sync app)
                              ↑
                  Obsidian opens local folder
```

- Syncthing daemon on freeBox; **Möbius Sync** on iPhone (Syncthing-compatible iOS client, ~$5 one-time on the App Store).
- Obsidian on iPhone opens the synced folder under "On my iPhone".
- Real-time peer-to-peer; works great over Tailscale.
- No Obsidian Sync subscription, no Mac, no cloud middleman.

**Pros:** real-time, fully self-hosted, no recurring fees, only your devices touch the data.
**Cons:** Möbius Sync isn't free; iOS background sync is best-effort (Apple limits background time, so the phone may need to be foregrounded briefly to catch up); initial pairing is fiddlier than tapping "subscribe".

### Option C — Git + Working Copy

```
[ freeBox: vault as git repo ]
        ↑                    ↑
    Claude commits      iPhone pulls/pushes
                              ↑
                   Working Copy app on iPhone
                              ↓
                   Obsidian opens that folder
```

- Each vault is a git repo on freeBox. Claude commits changes (manually or via a Claude command).
- **Working Copy** (iOS git client, free for read, ~$20 one-time for full write) clones the repo to iPhone storage.
- Obsidian on iPhone opens the Working Copy folder as a vault.
- Push from phone, pull on server, or vice versa, on demand.

**Pros:** version history for free, works completely offline, very robust, uses tools you already understand.
**Cons:** **not real-time** — you have to pull/push manually (or wire up automation). Merge conflicts on long markdown files are manageable; on attachments (PDFs, images) they're painful. Working Copy's full features cost money.

### Option D — WebDAV + Remotely Save plugin

```
[ freeBox: nginx/apache + WebDAV ]
              ↑                ↑
         Claude edits     Obsidian "Remotely Save"
         the files        plugin syncs vault
                                ↑
                          iPhone Obsidian
```

- Run a WebDAV server on freeBox (nginx with `webdav` module, or `webdav-cli`).
- Install the **"Remotely Save"** community plugin in Obsidian on iPhone, point it at your WebDAV endpoint.
- The plugin syncs the vault to/from WebDAV on demand or on a schedule.

**Pros:** no extra iOS app needed, Obsidian handles the sync directly, fully self-hosted.
**Cons:** WebDAV is fiddly to set up correctly (auth, locking, large files); "Remotely Save" is community-maintained, not official; sync is on-demand, not real-time; reliability varies.

### Option E — iPad as the bridge (if you have one)

Same as Option A, but the iPad runs Obsidian + Obsidian Sync instead of the Mac. The iPad becomes the "always-on bridge". Less practical than Mac because iPad is more often asleep, but it removes the Mac requirement.

### Option F — Don't sync, just SSH to the server from iPhone

- Use **Blink Shell**, **Termius**, or similar on iPhone to SSH to freeBox and work directly there (Claude in tmux, edit markdown via Claude or `nano`/`vim`).
- The vault never leaves the server.
- You give up the iPhone Obsidian app entirely for these vaults.

**Pros:** zero sync infrastructure, zero state to keep consistent, works today.
**Cons:** no Obsidian iOS editor, no offline access, depends on Tailscale/SSH being reachable.

---

## Option G — Don't put main vaults on the server at all

- freeBox is for repos, code, scratch markdown, and "working" copies you `git pull` when you want to.
- Main Obsidian vaults stay on iPhone (and any other Obsidian device) via Obsidian Sync as today, untouched.
- Smallest blast radius, no new sync infrastructure, nothing to maintain.

**When this is the right answer:** if "Claude editing my main vault from the server" is not actually a daily need yet, this avoids spending hours on a sync layer for a problem that doesn't exist.

---

## Honest recommendation (revisit after picking a direction)

**Without a Mac in the picture, the realistic Mac-less ranking is:**

1. **Option B (Syncthing + Möbius Sync)** — best for "I want my server to be the home of the vault and my phone to see changes shortly after they happen." The $5 for Möbius is worth it.
2. **Option C (Git + Working Copy)** — best if you already think in git, are OK with manual sync, and want version history for free. Avoid for vaults with lots of binary attachments.
3. **Option F (just SSH from iPhone)** — best if the Obsidian *iOS app* isn't actually load-bearing for these vaults. Brutally simple.
4. **Option G (don't sync at all)** — best if "Claude on vault" is aspirational rather than a current need.
5. Option D (WebDAV) is technically possible but I'd only pick it if you specifically want zero new iOS apps and are willing to babysit the WebDAV setup.

**With a Mac available**, Option A is the path of least surprise as long as you accept the Mac-must-be-on caveat.

---

## Open questions to answer before deciding

- Which vaults are important enough to live on the server?
- Real-time sync needed, or is "eventual within an hour" fine?
- Currently paying for Obsidian Sync? Happy with it?
- Willing to spend ~$5 (Möbius) or ~$20 (Working Copy) one-time on iOS?
- Should each vault get its own dedicated Claude tmux session, as captured in `TODO.md`?
- Is iCloud-style "it just works" automation important, or is "I run a sync command when I want" acceptable?

---

## Once you decide

Move the chosen option from this comparison doc into `setup.md` as concrete steps, and update `TODO.md` to track the install/configuration work.
