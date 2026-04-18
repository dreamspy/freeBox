#!/usr/bin/env python3
"""
SilverBullet vault launcher for freeBox.

Listens on 127.0.0.1:3001. Reachable from the tailnet via:
    tailscale serve --bg --https=443 --set-path=/launcher http://127.0.0.1:3001

Renders a vault picker page. Tapping a vault POSTs to /launcher/switch,
which runs `sb-switch <vault>` and returns a "switched" page with a button
to jump into the SilverBullet PWA.

Stdlib only — no external dependencies. Run as a systemd service so it
survives reboots. See CLAUDE.md / 10_docs/setup.md for the deployment.

Security notes:
- Binds to 127.0.0.1 only. Public reach is via Tailscale Serve, which is
  tailnet-only by default. Anyone on your tailnet can switch vaults — same
  trust boundary as `ssh freebox`.
- Validates vault names against the actual directory listing before running
  sb-switch (so no path traversal / arbitrary command injection).
"""
import json
import os
import subprocess
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

VAULTS_DIR = "/home/frimann/Vaults"
SB_SWITCH = "/home/frimann/bin/sb-switch"
VAULTS_UP = "/home/frimann/Programming/freeBox/20_scripts/freebox-vaults-up.sh"
SB_URL = "https://freebox.tail3eed93.ts.net/"
HOST = "127.0.0.1"
PORT = 3001

# Web App Manifest — pins the iOS PWA "home" to /launcher so the launcher
# never gets stuck on SB after the user taps "Open SilverBullet". Without
# this, iOS treats whatever URL the PWA was at last as the next launch URL.
MANIFEST = {
    "name": "freeBox SB Launcher",
    "short_name": "SB Vaults",
    "start_url": "/launcher",
    "scope": "/launcher/",
    "display": "standalone",
    "background_color": "#1a1a1a",
    "theme_color": "#1a1a1a",
    "icons": [
        {
            "src": "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>📚</text></svg>",
            "sizes": "any",
            "type": "image/svg+xml",
        }
    ],
}


def list_vaults():
    """Return sorted list of vault names: every non-hidden subdirectory of
    VAULTS_DIR. The user manages what lives here; the launcher just lists
    whatever directories exist (so adding/removing a vault on disk is the
    only step needed — no launcher edits)."""
    try:
        entries = sorted(os.listdir(VAULTS_DIR))
    except OSError:
        return []
    vaults = []
    for name in entries:
        if name.startswith("."):
            continue
        if not os.path.isdir(os.path.join(VAULTS_DIR, name)):
            continue
        vaults.append(name)
    return vaults


def html_escape(s):
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&#39;")
    )


def render_html(message=None, success=False):
    """Render the vault picker page. If `message` is set, show it as a
    status banner above the vault list."""
    vaults = list_vaults()
    parts = []
    parts.append("<!doctype html><html lang=en><head><meta charset=utf-8>")
    parts.append("<meta name=viewport content='width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no'>")
    parts.append("<title>freeBox SB Launcher</title>")
    # Web App Manifest — pins iOS PWA start_url to /launcher
    parts.append("<link rel='manifest' href='/launcher/manifest.json'>")
    # iOS PWA install hints
    parts.append("<link rel='apple-touch-icon' href=\"data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>📚</text></svg>\">")
    parts.append("<meta name=apple-mobile-web-app-capable content=yes>")
    parts.append("<meta name=apple-mobile-web-app-status-bar-style content=black-translucent>")
    parts.append("<meta name=apple-mobile-web-app-title content='SB Vaults'>")
    parts.append("""<style>
:root{color-scheme:dark}
*{box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',system-ui,sans-serif;max-width:480px;margin:0 auto;padding:max(1.5rem,env(safe-area-inset-top)) 1.5rem max(1.5rem,env(safe-area-inset-bottom));background:#1a1a1a;color:#e8e8e8;-webkit-text-size-adjust:100%}
h1{font-size:1.4rem;margin:0 0 1rem}
p{color:#999;font-size:.9rem;margin:.5rem 0 1.5rem}
form{margin:0}
button.vault{display:flex;align-items:center;width:100%;text-align:left;padding:1rem 1.25rem;margin:.6rem 0;font-size:1.05rem;background:#262626;color:#e8e8e8;border:1px solid #3a3a3a;border-radius:10px;cursor:pointer;font-weight:500;-webkit-tap-highlight-color:transparent}
button.vault:active{background:#333;transform:scale(.99)}
.msg{padding:1rem 1.25rem;border-radius:10px;margin-bottom:1rem;font-size:.95rem}
.msg.ok{background:#1f3f1f;border:1px solid #2d5a2d;color:#bfeebf}
.msg.err{background:#3f1f1f;border:1px solid #5a2d2d;color:#eebfbf}
a.open-sb{display:block;text-align:center;padding:1.1rem;background:#2d4d8a;color:#fff;text-decoration:none;border-radius:10px;margin-bottom:1.5rem;font-weight:600;font-size:1.05rem;-webkit-tap-highlight-color:transparent}
a.open-sb:active{background:#3a5a9a}
hr{border:none;border-top:1px solid #2a2a2a;margin:1.5rem 0}
button.action{display:block;width:100%;text-align:center;padding:1rem 1.25rem;margin:.6rem 0;font-size:.95rem;background:#2a2a2a;color:#999;border:1px solid #3a3a3a;border-radius:10px;cursor:pointer;font-weight:500;-webkit-tap-highlight-color:transparent}
button.action:active{background:#333;color:#ccc;transform:scale(.99)}
</style>""")
    parts.append("</head><body>")
    parts.append("<h1>📚 freeBox SB vaults</h1>")

    if message:
        css = "ok" if success else "err"
        parts.append(f"<div class='msg {css}'>{message}</div>")
        if success:
            # target=_blank rel=noopener so iOS opens SB in Safari rather
            # than navigating within the launcher PWA shell — keeps the
            # launcher PWA pinned to /launcher.
            parts.append(
                f"<a class=open-sb href='{html_escape(SB_URL)}' "
                "target=_blank rel=noopener>Open SilverBullet →</a>"
            )
            parts.append("<hr>")

    parts.append("<p>Tap a vault to switch the SilverBullet container to it.</p>")

    for v in vaults:
        v_esc = html_escape(v)
        parts.append("<form method=post action='/launcher/switch'>")
        parts.append(f"<input type=hidden name=vault value='{v_esc}'>")
        parts.append(f"<button class=vault type=submit>{v_esc}</button>")
        parts.append("</form>")

    parts.append("<hr>")
    parts.append("<form method=post action='/launcher/restart-claude'>")
    parts.append("<button class=action type=submit>🔄 Restart Claude sessions</button>")
    parts.append("</form>")

    parts.append("</body></html>")
    return "".join(parts).encode("utf-8")


def switch_vault(vault):
    """Run sb-switch with the given vault name. Validates the name against
    the live filesystem listing first to block injection / path traversal.
    Returns (ok, message)."""
    if vault not in list_vaults():
        return False, f"Unknown vault: {html_escape(vault)}"
    try:
        result = subprocess.run(
            [SB_SWITCH, vault],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        return False, "Timed out switching vault (sb-switch took &gt;30s)"
    except Exception as e:
        return False, f"Error: {html_escape(str(e))}"

    if result.returncode != 0:
        err = (result.stderr or result.stdout or "unknown error").strip()
        return False, f"sb-switch failed: <pre>{html_escape(err)}</pre>"

    return True, f"Switched to <strong>{html_escape(vault)}</strong>. SilverBullet is restarting (5–10s)."


def restart_claude_sessions():
    """Kill all vault-* tmux sessions, then re-run freebox-vaults-up.sh to
    recreate them. Returns (ok, message)."""
    # Kill existing vault-* sessions so freebox-vaults-up.sh recreates them
    try:
        ls_result = subprocess.run(
            ["tmux", "ls", "-F", "#{session_name}"],
            capture_output=True, text=True, timeout=5,
        )
        if ls_result.returncode == 0:
            for line in ls_result.stdout.strip().splitlines():
                if line.startswith("vault-"):
                    subprocess.run(
                        ["tmux", "kill-session", "-t", line],
                        capture_output=True, timeout=5,
                    )
    except Exception:
        pass  # No sessions to kill, or tmux not running — fine either way

    try:
        result = subprocess.run(
            ["bash", VAULTS_UP],
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        return False, "Timed out restarting Claude sessions (&gt;60s)"
    except Exception as e:
        return False, f"Error: {html_escape(str(e))}"

    if result.returncode != 0:
        err = (result.stderr or result.stdout or "unknown error").strip()
        return False, f"Restart failed: <pre>{html_escape(err)}</pre>"

    output = (result.stdout or "").strip()
    return True, f"Claude sessions restarted.<br><pre>{html_escape(output)}</pre>"


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, body, content_type="text/html; charset=utf-8"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        # tailscale serve --set-path=/launcher strips the /launcher prefix
        # before forwarding, so the backend sees "/" rather than "/launcher".
        # Accept both forms so the launcher is robust regardless of mount.
        path = self.path.split("?", 1)[0]
        if path in ("/", "/launcher", "/launcher/"):
            self._send(200, render_html())
        elif path in ("/manifest.json", "/launcher/manifest.json"):
            body = json.dumps(MANIFEST).encode("utf-8")
            self._send(200, body, "application/manifest+json")
        else:
            self._send(404, b"not found", "text/plain")

    def do_POST(self):
        # Same prefix-stripping caveat as do_GET — accept both forms.
        path = self.path.split("?", 1)[0]
        if path in ("/switch", "/launcher/switch"):
            length = int(self.headers.get("Content-Length", 0) or 0)
            data = self.rfile.read(length).decode("utf-8", errors="replace")
            params = urllib.parse.parse_qs(data)
            vault = params.get("vault", [""])[0]
            ok, message = switch_vault(vault)
            self._send(200 if ok else 500, render_html(message, success=ok))
        elif path in ("/restart-claude", "/launcher/restart-claude"):
            ok, message = restart_claude_sessions()
            self._send(200 if ok else 500, render_html(message, success=False))
        else:
            self._send(404, b"not found", "text/plain")

    def log_message(self, format, *args):
        # Quieter logging — systemd journal would otherwise get noisy
        return


if __name__ == "__main__":
    print(f"sb-launcher listening on http://{HOST}:{PORT}/", flush=True)
    HTTPServer((HOST, PORT), Handler).serve_forever()
