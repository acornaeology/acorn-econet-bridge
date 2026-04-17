#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""Refresh shared-code.json with the latest cross-ROM matches.

Runs `find-shared` against every sibling-repo ROM plus (if built) the
OS 1.20 ACME binary at /Users/rjs/Code/os120/os120.bin, then merges the
results into shared-code.json at the repo root.

Merging policy:

- Regions keyed by Bridge primary address (e.g. "0xE3EF").
- For regions present in the latest scan: replace the `peers` list
  and update `primary_instructions`/`primary_bytes` to the maximum
  observed across the new peers. Preserve the curated `name` and
  `notes` fields untouched.
- For regions in shared-code.json but absent from the latest scan:
  leave intact and print a warning. The curated notes remain useful
  even if the matcher no longer sees the span (e.g. because labels
  were renamed in a sibling).
- For regions in the latest scan but not in shared-code.json: append
  with `name` and `notes` set to null.

Usage:

    uv run tools/refresh_shared_code.py [--min-len N]

After running, render the Markdown view with:

    uv run tools/render_shared_code.py
"""

import argparse
import datetime
import json
import os
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ACORNAEOLOGY_ROOT = REPO_ROOT.parent
SHARED_CODE_FILEPATH = REPO_ROOT / "shared-code.json"

# Extend PYTHONPATH so the import below works when the script is run
# via `uv run` from the project .venv.
sys.path.insert(0, str(REPO_ROOT / "src"))

from disasm_tools.find_shared import (  # noqa: E402
    find_matching_spans,
    load_rom,
)
from disasm_tools.mos6502 import ROM_BASE  # noqa: E402


def collect_references():
    """Return list of (label, path, load_addr) for every sibling ROM.

    Silently skips repos that aren't checked out.
    """
    refs = []

    nfs_dirpath = ACORNAEOLOGY_ROOT / "acorn-nfs" / "versions"
    if nfs_dirpath.is_dir():
        for version_dir in sorted(nfs_dirpath.iterdir()):
            if not version_dir.is_dir():
                continue
            prefix, _, version_id = version_dir.name.partition("-")
            rom_filepath = (version_dir / "rom" /
                            f"{prefix}-{version_id}.rom")
            if rom_filepath.exists():
                refs.append((f"{prefix}-{version_id}", rom_filepath, 0x8000))

    # Tube client: upper 2 KB only, mapped at &F800
    tube_rom_filepath = (
        ACORNAEOLOGY_ROOT / "acorn-6502-tube-client" / "versions" /
        "tube-6502-client-1.10" / "rom" / "tube-6502-client-1.10.rom"
    )
    if tube_rom_filepath.exists():
        mapped_bytes = tube_rom_filepath.read_bytes()[2048:]
        tmp = tempfile.NamedTemporaryFile(
            prefix="tube-6502-client-1.10-mapped-", suffix=".rom",
            delete=False,
        )
        tmp.write(mapped_bytes)
        tmp.close()
        refs.append(("tube-6502-client-1.10", Path(tmp.name), 0xF800))

    adfs_rom_filepath = (
        ACORNAEOLOGY_ROOT / "acorn-adfs" / "versions" / "adfs-1.30" /
        "rom" / "adfs-1.30.rom"
    )
    if adfs_rom_filepath.exists():
        refs.append(("adfs-1.30", adfs_rom_filepath, 0x8000))

    os120_bin_filepath = Path("/Users/rjs/Code/os120/os120.bin")
    if os120_bin_filepath.exists():
        refs.append(("mos-1.20", os120_bin_filepath, 0xC000))

    return refs


def scan(primary_label, primary_path, primary_base, references, min_len):
    """Run find_matching_spans across all references, grouped by bridge addr.

    Returns dict keyed by bridge runtime address (int) mapping to:
        {"primary_instructions": int,
         "primary_bytes": int,
         "peers": [ {"rom": str, "address": int, "instructions": int,
                     "bytes": int}, ... ]}
    """
    primary = load_rom(primary_label, primary_path, primary_base)
    regions_by_addr = {}

    for ref_label, ref_path, ref_base in references:
        reference = load_rom(ref_label, ref_path, ref_base)
        matches = find_matching_spans(primary, reference, min_len)
        for a_idx, b_idx, size in matches:
            a_addr = primary.runtime_addr(a_idx)
            b_addr = reference.runtime_addr(b_idx)
            # Number of bytes of Bridge consumed by the matching span
            a_end_idx = a_idx + size
            a_end_offset = (primary.instructions[a_end_idx].offset
                            if a_end_idx < len(primary.instructions)
                            else len(primary.data))
            span_bytes = a_end_offset - primary.instructions[a_idx].offset

            region = regions_by_addr.setdefault(a_addr, {
                "primary_instructions": size,
                "primary_bytes": span_bytes,
                "peers": [],
            })
            region["primary_instructions"] = max(
                region["primary_instructions"], size
            )
            region["primary_bytes"] = max(region["primary_bytes"], span_bytes)
            region["peers"].append({
                "rom": ref_label,
                "address": b_addr,
                "instructions": size,
                "bytes": span_bytes,
            })

    return regions_by_addr


def load_existing():
    if not SHARED_CODE_FILEPATH.exists():
        return None
    return json.loads(SHARED_CODE_FILEPATH.read_text())


def merge(existing, scan_result, primary_label, primary_base, min_len,
          reference_labels):
    """Merge the scan result into the existing JSON, preserving notes."""
    existing_regions = {}
    if existing is not None:
        for region in existing.get("regions", []):
            key = int(region["primary_address"], 16)
            existing_regions[key] = region

    regions = []
    new_count = 0
    updated_count = 0
    stale_count = 0

    scanned_addrs = set(scan_result.keys())

    # Regions from the scan (new or updated)
    for addr in sorted(scanned_addrs):
        info = scan_result[addr]
        prev = existing_regions.get(addr)
        region = {
            "primary_address": f"0x{addr:04X}",
            "primary_instructions": info["primary_instructions"],
            "primary_bytes": info["primary_bytes"],
            "name": (prev or {}).get("name"),
            "notes": (prev or {}).get("notes"),
            "peers": [
                {
                    "rom": p["rom"],
                    "address": f"0x{p['address']:04X}",
                    "instructions": p["instructions"],
                    "bytes": p["bytes"],
                }
                for p in sorted(
                    info["peers"],
                    key=lambda p: (p["rom"], p["address"]),
                )
            ],
        }
        regions.append(region)
        if prev is None:
            new_count += 1
        else:
            updated_count += 1

    # Regions in existing JSON but not in scan: preserve, mark stale
    for addr in sorted(existing_regions.keys() - scanned_addrs):
        prev = dict(existing_regions[addr])
        prev.setdefault("stale", True)
        regions.append(prev)
        stale_count += 1

    # Sort all regions by address
    regions.sort(key=lambda r: int(r["primary_address"], 16))

    return {
        "primary": {
            "rom": primary_label,
            "load_addr": f"0x{primary_base:04X}",
        },
        "scan": {
            "min_len_instructions": min_len,
            "reject_trivial_distinct_below": 3,
            "references_included": reference_labels,
            "last_refreshed": datetime.date.today().isoformat(),
        },
        "regions": regions,
    }, (new_count, updated_count, stale_count)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--min-len", type=int, default=8,
                        help="Minimum matching instruction span (default: 8)")
    parser.add_argument("--version", default="1",
                        help="Bridge version (default: 1)")
    args = parser.parse_args()

    prefix = "econet-bridge"
    primary_label = f"{prefix}-{args.version}"
    primary_path = (REPO_ROOT / "versions" / primary_label / "rom" /
                    f"{primary_label}.rom")
    if not primary_path.exists():
        print(f"Error: primary ROM not found: {primary_path}",
              file=sys.stderr)
        sys.exit(1)

    references = collect_references()
    if not references:
        print("Error: no reference ROMs found in sibling repos.",
              file=sys.stderr)
        sys.exit(1)

    print(f"Scanning {primary_label} against {len(references)} reference(s)"
          f" at min-len={args.min_len}...")

    scan_result = scan(primary_label, primary_path, ROM_BASE, references,
                       args.min_len)

    existing = load_existing()
    merged, (new_count, updated_count, stale_count) = merge(
        existing, scan_result, primary_label, ROM_BASE, args.min_len,
        reference_labels=[r[0] for r in references],
    )

    SHARED_CODE_FILEPATH.write_text(
        json.dumps(merged, indent=2) + "\n"
    )
    print(f"Wrote {SHARED_CODE_FILEPATH.relative_to(REPO_ROOT)}")
    print(f"  {len(merged['regions'])} regions total, "
          f"{new_count} new, {updated_count} updated, {stale_count} stale")
    if stale_count:
        print("  (stale regions kept to preserve curated name/notes; "
              "remove manually if no longer relevant)")


if __name__ == "__main__":
    main()
