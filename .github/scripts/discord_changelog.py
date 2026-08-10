#!/usr/bin/env python3
"""
Posts the latest CHANGELOG.md entry to a Discord webhook as one clean, PLAIN-TEXT
release announcement - no embed box. Discord then renders the markdown headings
big and auto-builds the CurseForge link card from the bare URL at the bottom
(exactly the look of a hand-written release post).

Since CHANGELOG.md is already written player-facing (clean bullets, no filenames),
this mostly reformats the top release section: the "## X.Y.Z - date" heading
becomes a big title + Released line, "### Section" headers become Discord headings,
and the CurseForge URL is appended so Discord makes the card.

Standard library only. Reads the webhook URL from DISCORD_WEBHOOK_URL (a GitHub
secret); if it's unset, prints a note and exits cleanly so a release never fails.
"""
import json
import os
import re
import sys
import urllib.request
import urllib.error

ADDON_NAME = "Xal's Xpedited Routes"
ADDON_EMOJI = "🗺️"
CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/xals-xpedited-routes"
CHANGELOG_PATH = "CHANGELOG.md"
MAX_CONTENT = 2000  # Discord's hard limit for a message's content field


def latest_section(text):
    """Return (heading, body) for the top-most '## X.Y.Z - date' block, or None.
    CHANGELOG.md only ever holds the current release, so the first '## ' heading
    IS the latest one - no need to match a literal word before the version."""
    parts = re.split(r"(?m)^##\s+", text)
    if len(parts) < 2:
        return None
    heading, _, body = parts[1].partition("\n")
    return heading.strip(), body


def parse_heading(heading):
    """'1.3.0 - August 6, 2026' -> ('1.3.0', 'August 6, 2026')."""
    m = re.match(r"\s*([^\s-]+)\s*-\s*(.+)", heading)
    if m:
        return m.group(1).strip(), m.group(2).strip()
    return heading, None


def build_content(version, date, body):
    """Plain-text Discord message: big title, Released line, section headings,
    bullets, then the download URL (bare, so Discord unfurls the CurseForge card)."""
    out = [f"# {ADDON_EMOJI} {ADDON_NAME} — {version}"]
    if date:
        out.append(f"**Released:** {date}")
    for raw in body.splitlines():
        line = raw.rstrip()
        if line.strip() == "---":
            continue  # drop the divider under the version heading
        m = re.match(r"^#{2,3}\s+(.*)$", line)  # "### Section" / "## Section"
        if m:
            out.append("")
            out.append(f"## {m.group(1).strip()}")
        else:
            out.append(line)
    text = "\n".join(out)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()  # collapse runs of blank lines
    return f"{text}\n\nDownload: {CURSEFORGE_URL}"


def main():
    webhook = os.environ.get("DISCORD_WEBHOOK_URL")
    if not webhook:
        print("DISCORD_WEBHOOK_URL not set - skipping Discord announcement.")
        return 0

    with open(CHANGELOG_PATH, encoding="utf-8") as fh:
        text = fh.read()

    section = latest_section(text)
    if not section:
        print("No '## X.Y.Z' version heading found in CHANGELOG.md - skipping.")
        return 0

    heading, body = section
    version, date = parse_heading(heading)
    content = build_content(version, date, body)
    if len(content) > MAX_CONTENT:
        content = content[:MAX_CONTENT - 20].rstrip() + "\n…"

    payload = {"content": content, "allowed_mentions": {"parse": []}}
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        webhook, data=data,
        headers={
            "Content-Type": "application/json",
            # Discord 403s urllib's default agent, so send an explicit User-Agent.
            "User-Agent": "XalsXpeditedRoutes-Release/1.0",
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            print(f"Posted release announcement to Discord (HTTP {resp.status}).")
    except urllib.error.HTTPError as err:
        detail = err.read().decode("utf-8", "ignore")
        print(f"Discord post FAILED: HTTP {err.code} - {detail}")
        return 1
    except urllib.error.URLError as err:
        print(f"Discord post FAILED: {err.reason}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
