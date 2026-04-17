#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# ///
"""Compare the Econet Bridge ROM against sibling-repo ROMs and, if
available, a locally-built OS 1.20 binary.

This is a convenience wrapper around `acorn-econet-bridge-disasm-tool
find-shared` that discovers the Acorn NFS, ANFS, and Tube Client ROMs
in sibling repositories under /Users/rjs/Code/acornaeology, and
optionally an `os120.bin` built from /Users/rjs/Code/os120.

OS 1.20 is not shipped as a binary; the ACME source needs to be
assembled first. See the DISASSEMBLY.md section on cross-ROM
comparisons for instructions.

Usage:

    uv run tools/find_shared_with_siblings.py [--min-len N] [--limit K]

The result is printed to stdout. Non-matching ROMs are skipped with a
warning but do not cause failure.
"""

import argparse
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
ACORNAEOLOGY_ROOT = REPO_ROOT.parent


def collect_reference_specs():
    """Build a list of [label=]path@load-addr specs for sibling ROMs.

    ROMs that can't be found are skipped with a warning (so this tool
    keeps working if the user has only checked out a subset of repos).
    """
    specs = []

    nfs_dirpath = ACORNAEOLOGY_ROOT / "acorn-nfs" / "versions"
    if nfs_dirpath.is_dir():
        for version_dir in sorted(nfs_dirpath.iterdir()):
            if not version_dir.is_dir():
                continue
            prefix, _, version_id = version_dir.name.partition("-")
            rom_filepath = (version_dir / "rom" /
                            f"{prefix}-{version_id}.rom")
            if rom_filepath.exists():
                specs.append(
                    f"{prefix}-{version_id}={rom_filepath}@0x8000"
                )

    tube_dirpath = (ACORNAEOLOGY_ROOT / "acorn-6502-tube-client" /
                    "versions" / "tube-6502-client-1.10")
    tube_rom_filepath = tube_dirpath / "rom" / "tube-6502-client-1.10.rom"
    if tube_rom_filepath.exists():
        # The physical 4 kB ROM has 2 kB of &FF padding followed by the
        # 2 kB of code that is mapped at &F800 on the parasite. Write
        # just the mapped portion out as a temp file so the comparison
        # doesn't false-match our own &FF padding against the Tube
        # padding.
        import tempfile
        mapped_bytes = tube_rom_filepath.read_bytes()[2048:]
        tmp = tempfile.NamedTemporaryFile(
            prefix="tube-6502-client-1.10-mapped-", suffix=".rom",
            delete=False,
        )
        tmp.write(mapped_bytes)
        tmp.close()
        specs.append(f"tube-6502-client-1.10={tmp.name}@0xF800")

    adfs_rom_filepath = (ACORNAEOLOGY_ROOT / "acorn-adfs" / "versions" /
                         "adfs-1.30" / "rom" / "adfs-1.30.rom")
    if adfs_rom_filepath.exists():
        specs.append(f"adfs-1.30={adfs_rom_filepath}@0x8000")

    os120_bin_filepath = Path("/Users/rjs/Code/os120/os120.bin")
    if os120_bin_filepath.exists():
        specs.append(f"mos-1.20={os120_bin_filepath}@0xC000")
    else:
        print(
            f"Note: {os120_bin_filepath} not found — skipping OS 1.20. "
            f"To include it, install ACME and run:",
            file=sys.stderr,
        )
        print(
            "    cd /Users/rjs/Code/os120 && "
            "acme -o os120.bin os120_acme.a",
            file=sys.stderr,
        )

    return specs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--min-len", type=int, default=8)
    parser.add_argument("--limit", type=int, default=10)
    parser.add_argument("--version", default="1",
                        help="Econet Bridge version (default: 1)")
    args = parser.parse_args()

    references = collect_reference_specs()
    if not references:
        print("Error: no reference ROMs found.", file=sys.stderr)
        sys.exit(1)

    cmd = [
        "uv", "run", "acorn-econet-bridge-disasm-tool",
        "find-shared", args.version,
        "--min-len", str(args.min_len),
        "--limit", str(args.limit),
        *references,
    ]
    result = subprocess.run(cmd, cwd=REPO_ROOT)
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
