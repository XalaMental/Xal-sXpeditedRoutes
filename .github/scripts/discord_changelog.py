#!/usr/bin/env python3
"""
Posts the latest CHANGELOG.md entry to a Discord webhook as one clean release
announcement per update. Run by the release workflow on a tag push.

It posts a PLAYER-FACING version: it strips the per-file "**Filename** -" prefixes
and drops the "Under the hood" section, so the announcement reads like a normal
patch note even though the source changelog is organized per file for commits.

Needs only the Python standard library. Reads the webhook URL from the
DISCORD_WEBHOOK_URL environment variable (a GitHub secret). If that isn't set,
it prints a note and exits cleanly - so it never fails a release.
"""
import json
import os
import re
import sys
import urllib.request
import urllib.error

# ------------------------------------------------------------------ config ----
ADDON_NAME = "Xal's Xpedited Routes"
ADDON_EMOJI = "🗺️"
CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/xals-xpedited-routes"  # ← VERIFY this slug
EMBED_COLOR = 0x1D9E75  # teal-green accent bar on the embed
CHANGELOG_PATH = "CHANGELOG.md"
SKIP_CATEGORIES = ()  # nothing dropped - the post shows every category / every file


def latest_section(text):
    """Return (heading, body) for the top-most '## Release ...' block, or None."""
    parts = re.split(r"(?m)^##\s+Release\b", text)
    if len(parts) < 2:
        return None
    heading, _, body = parts[1].partition("\n")
    return heading.strip(), body


def parse_heading(heading):
    """'1.1.1 - August 6, 2026' -> ('1.1.1', 'August 6, 2026')."""
    m = re.match(r"\s*([^\s-]+)\s*-\s*(.+)", heading)
    if m:
        return m.group(1).strip(), m.group(2).strip()
    return heading, None


def clean_bullet(line):
    """'- **RunTracker.lua** - Added the haul tracker' -> '- Added the haul tracker'."""
    m = re.match(r"^(\s*[-*]\s+)\*\*[^*]+\*\*\s*-\s*(.*)$", line)
    return (m.group(1) + m.group(2)) if m else line


def build_description(body, date):
    lines = []
    if date:
        lines.append(f"**Released:** {date}")
    skipping = False
    for raw in body.splitlines():
        line = raw.rstrip()
        if line.startswith("### "):
            cat = line[4:].strip()
            skipping = any(s in cat.lower() for s in SKIP_CATEGORIES)
            if not skipping:
                lines.append("")
                lines.append(f"**{cat}**")
            continue
        if skipping:
            continue
        if line.strip() in ("", "---"):
            continue
        if line.strip().startswith(("-", "*")):
            lines.append(clean_bullet(line))
        else:
            lines.append(line)
    return "\n".join(lines).strip()


def main():
    webhook = os.environ.get("DISCORD_WEBHOOK_URL")
    if not webhook:
        print("DISCORD_WEBHOOK_URL not set - skipping Discord announcement.")
        return 0

    with open(CHANGELOG_PATH, encoding="utf-8") as fh:
        text = fh.read()

    section = latest_section(text)
    if not section:
        print("No '## Release' section found in CHANGELOG.md - skipping.")
        return 0

    heading, body = section
    parsed_version, date = parse_heading(heading)

    description = build_description(body, date)

    payload = {
        "content": CURSEFORGE_URL,  # bare URL -> Discord renders the CurseForge card
        "embeds": [{
            "title": f"{ADDON_EMOJI} {ADDON_NAME} — Release {parsed_version}",
            "url": CURSEFORGE_URL,
            "description": description[:4000],
            "color": EMBED_COLOR,
        }],
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        webhook, data=data,
        headers={
            "Content-Type": "application/json",
            # Discord rejects webhook posts sent with urllib's default agent
            # (HTTP 403), so send an explicit User-Agent.
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
