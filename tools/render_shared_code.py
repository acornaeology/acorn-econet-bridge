#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""Render shared-code.json as a human-readable Markdown document.

Writes docs/SHARED-CODE.md, grouping regions by Bridge primary address
with a table of peer ROMs and addresses. Regions are sorted by:

1. Number of peers (broadest sharing first — these are the most
   load-bearing routines to understand)
2. Bridge primary address (ascending, as a tiebreaker)

Curated `name` and `notes` fields from the JSON are rendered inline.
Stale regions (previously scanned but not in the latest scan) are
rendered at the end in a separate section.

Usage:

    uv run tools/render_shared_code.py           # write docs/SHARED-CODE.md
    uv run tools/render_shared_code.py --check   # exit 1 if out of date
"""

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SHARED_CODE_FILEPATH = REPO_ROOT / "shared-code.json"
OUTPUT_FILEPATH = REPO_ROOT / "docs" / "SHARED-CODE.md"


def format_region_heading(region):
    addr = region["primary_address"].replace("0x", "&")
    name = region.get("name")
    instr = region["primary_instructions"]
    byte_count = region["primary_bytes"]
    if name:
        return f"### `{addr}` — {name} — {instr} instr, {byte_count} bytes"
    return f"### `{addr}` — (unnamed) — {instr} instr, {byte_count} bytes"


def format_region_body(region):
    lines = []
    notes = region.get("notes")
    if notes:
        lines.append(notes.strip())
        lines.append("")
    else:
        lines.append("*No curated notes yet.*")
        lines.append("")

    lines.append("| ROM | Address | Instructions | Bytes |")
    lines.append("|-----|---------|-------------:|------:|")
    for peer in region["peers"]:
        peer_addr = peer["address"].replace("0x", "&")
        lines.append(
            f"| `{peer['rom']}` | `{peer_addr}` | "
            f"{peer['instructions']} | {peer['bytes']} |"
        )
    return "\n".join(lines)


def render(data):
    primary = data["primary"]
    scan = data["scan"]
    primary_addr = primary["load_addr"].replace("0x", "&")

    lines = []
    lines.append("# Shared code regions")
    lines.append("")
    lines.append(
        f"This document catalogues regions of the Econet Bridge ROM "
        f"(`{primary['rom']}`, loaded at `{primary_addr}`) whose "
        f"opcode sequences also appear in other Acorn 6502 ROMs, as "
        f"detected by `tools/refresh_shared_code.py`."
    )
    lines.append("")
    lines.append(
        f"Matching compares opcode bytes only, ignoring operands, so "
        f"the same routine at a different address in the peer ROM (or "
        f"touching different workspace variables) is still matched. "
        f"The trivial-span filter rejects matches with fewer than "
        f"{scan['reject_trivial_distinct_below']} distinct opcodes to "
        f"suppress false positives from padding regions."
    )
    lines.append("")
    lines.append(
        "Regions are listed in descending order of peer count — the "
        "most widely shared routines (likely the oldest and most "
        "foundational) appear first. The Bridge primary addresses "
        "link into the disassembly output; peer addresses into the "
        "relevant sibling repository's disassembly output."
    )
    lines.append("")
    lines.append("## Scan metadata")
    lines.append("")
    lines.append(f"- **Last refreshed:** {scan['last_refreshed']}")
    lines.append(
        f"- **Minimum match length:** "
        f"{scan['min_len_instructions']} instructions"
    )
    lines.append(
        f"- **Trivial-span floor:** "
        f"{scan['reject_trivial_distinct_below']} distinct opcodes"
    )
    lines.append(
        "- **References scanned:** "
        + ", ".join(f"`{r}`" for r in scan["references_included"])
    )
    lines.append("")

    active = [r for r in data["regions"] if not r.get("stale")]
    stale = [r for r in data["regions"] if r.get("stale")]

    active.sort(
        key=lambda r: (-len(r["peers"]), int(r["primary_address"], 16))
    )
    stale.sort(key=lambda r: int(r["primary_address"], 16))

    if active:
        lines.append(f"## Active regions ({len(active)})")
        lines.append("")
        for region in active:
            lines.append(format_region_heading(region))
            lines.append("")
            lines.append(format_region_body(region))
            lines.append("")
    else:
        lines.append("## Active regions")
        lines.append("")
        lines.append("*No regions in the latest scan.*")
        lines.append("")

    if stale:
        lines.append(f"## Stale regions ({len(stale)})")
        lines.append("")
        lines.append(
            "These regions were previously observed but did not appear "
            "in the most recent scan. Their curated names and notes are "
            "preserved here as archive. If the scan change was "
            "intentional, remove the entry from `shared-code.json`; "
            "otherwise investigate why the match was lost (e.g. a "
            "peer ROM was relabelled or padded differently)."
        )
        lines.append("")
        for region in stale:
            lines.append(format_region_heading(region))
            lines.append("")
            lines.append(format_region_body(region))
            lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", action="store_true",
                        help="Exit 1 if docs/SHARED-CODE.md is out of date")
    args = parser.parse_args()

    if not SHARED_CODE_FILEPATH.exists():
        print(f"Error: {SHARED_CODE_FILEPATH.name} not found. "
              f"Run tools/refresh_shared_code.py first.", file=sys.stderr)
        sys.exit(1)

    data = json.loads(SHARED_CODE_FILEPATH.read_text())
    rendered = render(data)

    OUTPUT_FILEPATH.parent.mkdir(parents=True, exist_ok=True)

    if args.check:
        if not OUTPUT_FILEPATH.exists() or OUTPUT_FILEPATH.read_text() != rendered:
            print(
                f"{OUTPUT_FILEPATH.relative_to(REPO_ROOT)} is out of date. "
                f"Run 'uv run tools/render_shared_code.py' and commit the "
                f"result.",
                file=sys.stderr,
            )
            sys.exit(1)
        print(f"{OUTPUT_FILEPATH.relative_to(REPO_ROOT)} is up to date.")
    else:
        OUTPUT_FILEPATH.write_text(rendered)
        print(f"Wrote {OUTPUT_FILEPATH.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()
