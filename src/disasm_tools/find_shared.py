"""Find shared code fragments between two or more 6502 ROM binaries.

Performs opcode-sequence comparison between a 'primary' ROM (typically
the current project's ROM) and one or more 'reference' ROMs. Uses the
same opcode-level SequenceMatcher approach as the address-map tooling:
only the opcode bytes are compared, operand bytes are ignored. This
means instructions with different operands but the same opcode (e.g.
`LDA &1234` vs `LDA &5678`) are still recognised as structurally
identical.

Matches are reported as spans of N or more consecutive matched
instructions, annotated with the runtime address of the first
instruction in each ROM.

Typical use cases:
- Identify code shared between firmware variants
- Detect routines borrowed from the MOS or another filing system
- Find reused utility routines across unrelated ROMs
"""

import argparse
import difflib
import sys
from dataclasses import dataclass
from pathlib import Path

from disasm_tools.mos6502 import OPCODE_LENGTHS


@dataclass
class Instruction:
    """A single instruction extracted from a ROM binary."""
    offset: int             # byte offset into the ROM
    opcode: int             # opcode byte
    length: int             # instruction length in bytes (1, 2 or 3)


@dataclass
class RomData:
    """An opcode-sweep of a ROM binary, paired with a load address."""
    label: str              # human-readable label (e.g. "econet-bridge-1")
    load_addr: int          # address at which the ROM is mapped
    data: bytes             # raw ROM contents
    instructions: list      # list[Instruction] from linear sweep
    opcodes: list           # list[int] — just the opcode bytes

    def runtime_addr(self, instruction_index):
        """Runtime address of the Nth instruction in the sweep."""
        return self.load_addr + self.instructions[instruction_index].offset


def sweep_opcodes(data: bytes):
    """Linear sweep of a ROM binary, returning (instructions, opcodes).

    The sweep is naive: it assumes every byte is the start of an
    instruction. This produces some noise in embedded data regions, but
    is robust across dispatch tables and relocated blocks. Matching
    spans in the output of this sweep are therefore suggestive, not
    authoritative.
    """
    instructions = []
    offset = 0
    while offset < len(data):
        opcode = data[offset]
        length = OPCODE_LENGTHS[opcode]
        if length == 0 or offset + length > len(data):
            length = 1
        instructions.append(Instruction(offset, opcode, length))
        offset += length
    opcodes = [i.opcode for i in instructions]
    return instructions, opcodes


def load_rom(label: str, filepath: Path, load_addr: int) -> RomData:
    """Load a ROM binary and prepare it for comparison."""
    data = filepath.read_bytes()
    instructions, opcodes = sweep_opcodes(data)
    return RomData(label, load_addr, data, instructions, opcodes)


def _is_trivial_span(opcodes, start, length, min_distinct=3):
    """A span is trivial if it contains fewer than `min_distinct` opcodes.

    This filters out spurious matches in ROM padding (runs of &FF or
    &00) and degenerate patterns like 'one RTS followed by padding'.
    Without this filter, any two ROMs with similar-sized padding
    regions would appear to share thousands of bytes of 'code', and
    sub-shaped sequences like `60 FF FF FF ...` would produce long
    bogus matches.
    """
    window = opcodes[start:start + length]
    return len(set(window)) < min_distinct


def find_matching_spans(primary: RomData, reference: RomData, min_len: int,
                        reject_trivial: bool = True):
    """Find spans of matching opcodes between two sweeps.

    Returns a list of (primary_idx, reference_idx, length) tuples for
    every matching block of at least `min_len` instructions.
    """
    matcher = difflib.SequenceMatcher(a=primary.opcodes, b=reference.opcodes,
                                      autojunk=False)
    matches = []
    for block in matcher.get_matching_blocks():
        if block.size < min_len:
            continue
        if reject_trivial and _is_trivial_span(primary.opcodes, block.a,
                                               block.size):
            continue
        matches.append((block.a, block.b, block.size))
    return matches


def matching_byte_count(primary: RomData, reference: RomData,
                        matches) -> int:
    """Sum of instruction byte-lengths across matching spans in primary."""
    total = 0
    for a_idx, _, size in matches:
        for i in range(a_idx, a_idx + size):
            total += primary.instructions[i].length
    return total


def report_matches(primary: RomData, reference: RomData, matches,
                   stream=sys.stdout, limit=None):
    """Pretty-print matching spans to the given stream."""
    matches_sorted = sorted(matches, key=lambda m: -m[2])
    if limit is not None:
        matches_sorted = matches_sorted[:limit]

    stream.write(f"\n=== {primary.label}  vs  {reference.label} ===\n")

    if not matches:
        stream.write("  (no matches at or above minimum length)\n")
        return

    total_matched = matching_byte_count(primary, reference, matches)
    pct_primary = 100.0 * total_matched / max(len(primary.data), 1)
    stream.write(
        f"  {len(matches)} matching spans, "
        f"{total_matched} bytes of primary "
        f"({pct_primary:.1f}% of {primary.label})\n"
    )
    stream.write(
        f"  {'INSTR':>6}  {'BYTES':>6}  "
        f"{primary.label:>18}  {reference.label:>18}\n"
    )

    for a_idx, b_idx, size in matches_sorted:
        a_addr = primary.runtime_addr(a_idx)
        b_addr = reference.runtime_addr(b_idx)
        a_end_idx = a_idx + size
        a_end_offset = (primary.instructions[a_end_idx].offset
                        if a_end_idx < len(primary.instructions)
                        else len(primary.data))
        span_bytes = a_end_offset - primary.instructions[a_idx].offset
        stream.write(
            f"  {size:>6}  {span_bytes:>6}  "
            f"{a_addr:>6X}+{span_bytes:<10X}  "
            f"{b_addr:>6X}+{span_bytes:<10X}\n"
        )


def parse_rom_spec(spec: str):
    """Parse a ROM specification string 'label=path@base' or 'path@base'.

    Address may be given in hex (&E000, 0xE000, $E000) or decimal.
    If the label is omitted, the file stem is used.
    """
    if "=" in spec:
        label, rest = spec.split("=", 1)
    else:
        label, rest = None, spec

    if "@" not in rest:
        raise ValueError(
            f"ROM spec must include @<load-addr>: {spec!r}"
        )
    path_str, addr_str = rest.rsplit("@", 1)
    addr_str = addr_str.strip().lstrip("$&").removeprefix("0x")
    try:
        load_addr = int(addr_str, 16)
    except ValueError:
        raise ValueError(f"Invalid load address in {spec!r}: {addr_str!r}")

    path = Path(path_str).expanduser()
    if not path.exists():
        raise FileNotFoundError(f"ROM file not found: {path}")

    if label is None:
        label = path.stem
    return label, path, load_addr


def find_shared(primary_spec: str, reference_specs: list, min_len: int,
                limit=None):
    """Entry point: compare primary ROM against each reference ROM."""
    p_label, p_path, p_base = parse_rom_spec(primary_spec)
    primary = load_rom(p_label, p_path, p_base)
    print(
        f"Primary: {primary.label} "
        f"({len(primary.data)} bytes @ &{primary.load_addr:04X}, "
        f"{len(primary.instructions)} sweep instructions)"
    )

    for ref_spec in reference_specs:
        r_label, r_path, r_base = parse_rom_spec(ref_spec)
        reference = load_rom(r_label, r_path, r_base)
        print(
            f"Reference: {reference.label} "
            f"({len(reference.data)} bytes @ &{reference.load_addr:04X}, "
            f"{len(reference.instructions)} sweep instructions)"
        )
        matches = find_matching_spans(primary, reference, min_len)
        report_matches(primary, reference, matches, limit=limit)

    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="find-shared",
        description=(
            "Find shared 6502 code fragments between two or more ROM "
            "binaries using opcode-sequence matching."
        ),
    )
    parser.add_argument(
        "primary",
        help=(
            "Primary ROM spec: [label=]path@load-addr, e.g. "
            "econet=versions/econet-bridge-1/rom/econet-bridge-1.rom@&E000"
        ),
    )
    parser.add_argument(
        "references", nargs="+",
        help="Reference ROM specs (same format as primary)",
    )
    parser.add_argument(
        "--min-len", type=int, default=8,
        help="Minimum matching span length, in instructions (default: 8)",
    )
    parser.add_argument(
        "--limit", type=int, default=None,
        help="Show at most N longest matches per reference",
    )
    args = parser.parse_args(argv)

    return find_shared(args.primary, args.references, args.min_len, args.limit)


if __name__ == "__main__":
    sys.exit(main())
