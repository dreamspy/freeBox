# Linode VPS vs. Mac mini at home

Comparison of the current freeBox setup (Linode shared-CPU VPS) against running the same workload on a Mac mini at home. **Status: exploration, undecided.** This document weighs the trade-offs so the choice can be made deliberately rather than by inertia.

## Why this question is on the table

freeBox today is a Linode shared-CPU Ubuntu 24.04 VPS used for Claude Code in `tmux`, reachable over SSH and Tailscale. It works, but two pressures invite a rethink:

1. **Recurring cost vs. one-time cost.** A Linode bill arrives every month forever. A Mac mini is bought once.
2. **The Obsidian sync problem** (see `obsidian-sync.md`). Obsidian doesn't run on a headless Linux server, which forces awkward sync topologies. A Mac mini runs Obsidian natively and would dissolve that whole problem.

If neither of those mattered, "keep Linode" would be the obvious answer.

---

## At a glance

| Dimension | Linode (current) | Mac mini at home |
|---|---|---|
| **Cost shape** | ~$5–24/month forever | $400–800 once + ~$5–25/year electricity |
| **3-year total** | ~$180–860 | ~$415–875 (then near-zero) |
| **Hardware ownership** | None — provider's | You own it |
| **OS** | Ubuntu 24.04 (Linux) | macOS (or Linux in a VM) |
| **CPU** | 1–2 shared vCPUs | M2/M4 — way more headroom |
| **RAM** | 1–4 GB typical | 8–24 GB easily |
| **Storage** | 25–80 GB SSD | 256 GB–2 TB SSD |
| **Power use** | None for you | ~5 W idle, ~30 W peak |
| **Uptime model** | Datacenter (multi-ISP, UPS) | Your home (one ISP, one power) |
| **Public IP** | Static, given by Linode | ISP-dependent, often dynamic |
| **Reachable from anywhere** | Yes, via public IP or Tailscale | Yes via Tailscale; public IP optional and ISP-dependent |
| **Runs Obsidian natively** | ❌ No (headless Linux) | ✅ Yes |
| **Physical recovery access** | Web console only | You can plug in a screen |
| **Datacenter risks** | Provider outages, billing issues | None |
| **Home risks** | None | Power cuts, ISP outages, theft, fire, family unplugs it |
| **ISP TOS** | N/A | Many residential plans technically forbid servers; rarely enforced and Tailscale-only sidesteps it |
| **Setup tooling familiarity** | Strong (apt, systemd, Ubuntu) | Weaker for headless work (brew, launchd, macOS quirks) |

---

## Pros of switching to a Mac mini

**1. Obsidian becomes a non-problem.** This is the biggest single argument. A Mac mini can run Obsidian + Obsidian Sync natively, 24/7, as the always-on bridge between freeBox-side files and the iPhone. Most of the discussion in `10_docs/obsidian-sync.md` simply collapses: there's no longer a "Mac must be on" caveat because *the Mac mini is the always-on Mac*. Syncthing or even a plain shared folder is enough on top.

**2. Massive performance jump for the same money.** An M2/M4 Mac mini outperforms anything in Linode's shared-CPU lineup by a wide margin. RAM headroom in particular goes from cramped (1–4 GB) to comfortable (8–24 GB). Multiple Claude sessions, browser-based dev tools, and local LLMs all become realistic.

**3. No recurring bill.** After year ~2–3 of Linode at the cheaper plans (or year ~1 at higher plans), the Mac mini has paid for itself. Long-term cost graph crosses over and stays in your favor.

**4. Real hardware you own.** No risk of provider price hikes, no risk of account suspension, no risk of "your data is on someone else's computer." Backups are physical and accessible.

**5. Local LLM and ML work become viable.** M-series chips have a unified memory architecture and Neural Engine that make running 7B–13B models locally surprisingly usable. Linode shared CPU cannot do this.

**6. Quiet, cool, low power.** Modern Mac minis are fanless or near-silent and idle around 5 W. Even in a small apartment they disappear. Iceland electricity is cheap, so the running cost is negligible (~$5–15/year).

**7. Physical access for recovery.** When something is wrong with a Linode box you have a slow web console and that's it. With a Mac mini you can plug in a keyboard and screen.

---

## Cons of switching to a Mac mini

**1. Upfront cost.** A new M4 Mac mini base model is ~$599. A used M1/M2 mini is ~$400–500. That's real money up front, even though it's cheaper over multi-year horizons.

**2. Home network is now the SPOF.** If your apartment loses power or internet, freeBox is unreachable. Linode runs in a datacenter with UPS and multi-ISP redundancy. For a personal Claude box this is usually fine, but it *is* a regression on uptime.

**3. macOS is not Linux.** The bootstrap script, the documentation, the muscle memory — all of it assumes Ubuntu. On macOS you'd swap apt for Homebrew, systemd for launchd, ufw for pf/Little Snitch, and `/etc/ssh/sshd_config` lives in a different place. Most things have direct equivalents but everything in `10_docs/setup.md` would need a parallel macOS version (or you'd run Ubuntu in a VM, which adds its own friction).

**4. Server-grade tooling is weaker on macOS.** Container runtimes are second-class on macOS (Docker Desktop is heavyweight; OrbStack is better; both run a Linux VM under the hood). Long-running daemons via launchd are workable but quirkier than systemd. macOS background app limits and Sleep settings can bite you in unexpected ways.

**5. macOS update disruption.** macOS major upgrades reboot the machine and sometimes require interactive consent. A headless mac mini occasionally needs babysitting in ways a Linux server doesn't.

**6. Public IP from your ISP is messy.** Most home ISPs hand out dynamic addresses, sometimes behind CGNAT. Tailscale solves "I want to reach freeBox from my phone" completely, but if you ever need a real public-facing service (e.g. a webhook target), you'd need a tunnel like ngrok or Cloudflare Tunnel.

**7. ISP TOS.** Some residential internet plans forbid running servers. Enforcement is rare, especially for personal Tailscale-only use that never opens public ports — but it's a thing.

**8. Physical and human risk.** A datacenter doesn't get knocked off the desk by a cat, unplugged by a houseguest, or stolen in a burglary. Home risk is small but nonzero.

**9. The Obsidian Sync "Mac must be on" caveat collapses but doesn't fully disappear.** The mini is on 24/7, but Obsidian Sync still routes through Obsidian's cloud, which is a third-party dependency. If you want true zero-trust, you still want Syncthing.

---

## The Obsidian factor (the swing vote)

If you set Obsidian aside, this is roughly a coin flip — Linode wins on uptime and operational simplicity, Mac mini wins on cost-over-time and raw power.

But Obsidian is *not* a small detail in this project. Half the open work (per `TODO.md` and `10_docs/obsidian-sync.md`) is figuring out how to get vaults synced sensibly. A Mac mini running Obsidian natively turns that whole branch of work into a one-step setup ("install Obsidian, sign in, done"). That's worth a lot of friction elsewhere.

**If Obsidian-on-the-server is going to be a real workflow for you, the Mac mini's value proposition is much stronger than the table makes it look.**

If Obsidian-on-the-server is *not* going to be a real workflow (i.e. Option G in `obsidian-sync.md` — keep vaults on iPhone+Mac as today, never let freeBox touch them), the Mac mini's biggest single advantage evaporates and Linode looks more attractive by comparison.

---

## Cost over time (rough)

Assumes Linode at the $12/month tier (a reasonable 2 GB RAM plan), Mac mini at $599 base, Iceland electricity at ~$10/year for 24/7 idle.

| Horizon | Linode total | Mac mini total | Mac mini saves |
|---|---|---|---|
| Year 1 | $144 | $609 | –$465 (mini costs more) |
| Year 2 | $288 | $619 | –$331 |
| Year 3 | $432 | $629 | –$197 |
| Year 4 | $576 | $639 | –$63 |
| **Year 5** | **$720** | **$649** | **+$71** |
| Year 7 | $1,008 | $669 | +$339 |
| Year 10 | $1,440 | $699 | +$741 |

**Crossover is around year 4–5.** A used Mac mini at $400–500 brings the crossover to year 3. A cheaper Linode plan ($5/month) pushes the crossover out to year 8+.

Pure cost is rarely the deciding factor at these numbers — call it a tie unless you're optimizing for the long run or already owned the mini.

---

## Reliability comparison, honestly

| | Linode | Mac mini at home |
|---|---|---|
| Power outages | Datacenter UPS; rare | Home power; depends on grid |
| ISP outages | Datacenter has multiple uplinks | Single ISP, no redundancy |
| Hardware failure | Provider replaces; free | You replace; takes time |
| Software lockout | Web console recovery | Physical access |
| Account/billing risk | Suspension is possible | None |
| Theft / fire / accident | None | Nonzero |

For a personal Claude server, neither side is meaningfully fragile. Linode is genuinely more uptime-reliable, but the difference probably amounts to a few hours per year — and Tailscale will route around brief outages on either side as long as the box itself is up.

---

## Migration plan if you decide to switch

The repo as it stands assumes Ubuntu. Switching to a Mac mini requires either:

1. **macOS-native path** (recommended for Obsidian benefit):
   - Buy/repurpose Mac mini, set it up with auto-login disabled, FileVault on, automatic updates *manual* (so it doesn't reboot at random)
   - Install Homebrew, then `brew install tmux git ripgrep fd htop`
   - Install Tailscale (mac app), join the same tailnet, rename the device to `freeBox` (or pick a new name and update `~/.ssh/config`)
   - Install Claude Code on macOS
   - Install Obsidian, sign in to Obsidian Sync, point it at the vaults
   - Set the mini to never sleep (`sudo pmset -a sleep 0`), or sleep only the display
   - Add a launchd plist to keep a `tmux` session alive at boot
   - Fork `10_docs/setup.md` into `setup-macos.md` (or replace) with the macOS-equivalent commands
   - Update `bootstrap.sh` to detect macOS and branch, or write a separate `bootstrap-macos.sh`

2. **Ubuntu-VM-on-mac-mini path** (preserves all existing scripts):
   - Buy Mac mini, install OrbStack or UTM, run Ubuntu 24.04 in a VM
   - Point Tailscale at the VM (or at the host and forward)
   - Existing `bootstrap.sh` and `setup.md` work unchanged inside the VM
   - You give up the "Obsidian runs natively" advantage unless you also run Obsidian on the host
   - More complex; only worth it if you really value preserving the Linux scripts

3. **Hybrid path:** Mac mini hosts Obsidian and the vault, plus a small Ubuntu VM for the Claude/dev environment, with a shared folder between them. Best of both worlds at the cost of more moving parts.

In all cases:
- Cancel Linode only after the new box has been running fine for at least a week
- Update `SECRETS.md`, `CLAUDE.md`, `TODO.md`, and `~/.ssh/config` to reflect the new freeBox identity
- Consider keeping the Linode IP reservation for a month in case rollback is needed

---

## Honest recommendation

**If you have a real Obsidian-on-server workflow in mind, or you already own a Mac mini you can repurpose → switch.** The Obsidian advantage alone is worth it, the performance is a bonus, and the cost works out within a few years.

**If you're indifferent on Obsidian and just want a reliable place for Claude Code to live → stay on Linode.** It's working, the uptime is better, the bill is small at the cheaper tiers, and switching is real work for limited gain.

**If you're somewhere in between → buy a used M1/M2 Mac mini ($400–500), set it up alongside Linode without canceling, run them in parallel for a month, and let the actual experience decide.** Lowest-risk way to find out if the Mac mini approach holds up under your real workflow.

---

## Open questions

- Do you already own a Mac mini, an old MacBook, or another always-on Mac you could repurpose for this?
- Is your home internet reliable enough day-to-day that a few hours of monthly downtime would be acceptable?
- Is your ISP residential or business-class? Any explicit terms against running servers?
- How important is the Obsidian-on-server workflow really, on a scale of "essential" to "nice to imagine"? Be honest — this is the swing vote.
- Are you willing to maintain a parallel macOS variant of `setup.md` and `bootstrap.sh`, or would you prefer to keep everything Linux-native (which pushes you toward the VM path)?
- Long-term horizon: do you expect to keep this setup running for 3+ years? (Crossover math depends on this.)
