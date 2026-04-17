# Disassembly Guide

How to produce annotated, verified disassemblies of the Acorn Econet Bridge ROM.

For project overview and build instructions, see [README.md](README.md). For architecture details, see [CLAUDE.md](CLAUDE.md). For terminology, see [GLOSSARY.md](GLOSSARY.md).


## Prerequisites

- [uv](https://docs.astral.sh/uv/) for Python dependency management
- [beebasm](https://github.com/stardot/beebasm) (v1.10+) for assembly verification
- The ROM binary (8192 bytes) for the version being disassembled
- MD5 and SHA-256 hashes of the ROM (`md5 <rom>`, `shasum -a 256 <rom>`)


## Quick reference: CLI tools

All tools are invoked via `uv run acorn-econet-bridge-disasm-tool <command>`.

| Command | Description | Example |
|---------|-------------|---------|
| `disassemble` | Generate `.asm` and `.json` from ROM | `... disassemble 1` |
| `verify` | Reassemble and byte-compare against original ROM | `... verify 1` |
| `lint` | Validate annotation addresses and check for duplicates | `... lint 1` |
| `compare` | Compare two ROM versions (byte and opcode level) | `... compare 1 2` |
| `extract` | Extract assembly section by address range or label | `... extract 1 &E000 &E040` |
| `audit` | Audit subroutine annotations (summary, detail, flags) | `... audit 1 --summary` |
| `cfg` | Build inter-procedural call graph with depth ordering | `... cfg 1 --depth` |
| `context` | Generate per-subroutine context files for commenting | `... context 1 --sub E000` |
| `labels` | Generate per-label context files for renaming | `... labels 1 --summary` |
| `rename-labels` | Batch rename auto-generated labels | `... rename-labels 1 --file renames.txt` |
| `insert-point` | Find insertion point for new subroutine declaration | `... insert-point 1 &E000` |
| `comment-check` | Check inline comments against instruction data | `... comment-check 1` |
| `backfill` | Propagate annotations between versions | `... backfill 1 2` |
| `promote` | Find labels that should be promoted to entry points | `... promote 1` |
| `find-shared` | Find shared 6502 code fragments vs. reference ROMs | `... find-shared 1 nfs=path@&8000` |

The `extract` command accepts hex addresses in multiple formats (`&E000`, `$E000`, `0xE000`) as well as label names.


## Producing a new version disassembly

### Step 1: Directory structure

Create the version directory tree:

```
versions/econet-bridge-<VER>/
  rom/
    econet-bridge-<VER>.rom    # The ROM binary
    rom.json                   # Metadata: title, size, md5, sha256
  disassemble/
    __init__.py                # Empty
    disasm_econet_bridge_<ver>.py  # Driver script (dots removed)
  output/                      # Generated .asm and .json go here
```

Update `acornaeology.json` to add the new version to the versions array.


### Step 2: Build the driver script

For the first version, start with a minimal driver that loads the ROM at &E000 and declares the CPU reset/IRQ vectors as entry points. For subsequent versions, use address mapping from the nearest existing version.


### Step 3: Iterate

Run:

```sh
uv run acorn-econet-bridge-disasm-tool disassemble <VER>
uv run acorn-econet-bridge-disasm-tool verify <VER>
```

Fix errors until verification passes, then annotate.


## py8dis driver script reference

The driver script configures py8dis using a Python DSL. Each call annotates the disassembly output.

### Core DSL calls

**`label(address, name)`** — Assign a symbolic name to a ROM or RAM address.

**`constant(name, value)`** — Define a named constant for a numeric value. Used for hardware register addresses, protocol codes, etc. The value is symbolic, not a ROM address.

**`comment(address, text)`** — Attach a comment to a specific instruction address.

**`subroutine(address, title, description)`** — Mark the start of a subroutine with a title and description.

**`entry(address)`** — Mark an address as a code entry point.

**`move(dest, source, length)`** — Declare a relocated code block.

**`hook_subroutine(address, hook_function)`** — Register a custom Python function for special handling of dispatch tables, inline data, etc.


## Annotation guidelines

### Subroutine descriptions

A good subroutine description:

- **Title**: A standalone phrase or short sentence summarising the routine's purpose.
- **Description**: Explains behaviour, entry/exit conditions, and side effects.
- **Calling convention**: Uses `On entry:` and `On exit:` blocks with indented register/flag details.

### Comment length

Assembly comments are formatted to fit within 62 characters (py8dis formatting constraint).

### Hex notation

- Use **Acorn notation** (`&XXXX`) in documentation, Markdown files, and human-readable output
- Use **Python notation** (`0xXXXX`) in Python scripts (driver scripts, tools)


## Key gotchas

1. **py8dis auto-labels can collide.** Any `return_N`, `loop_cXXXX`, etc. that appears in both main ROM and relocated code will cause beebasm duplicate label errors. Fix by adding explicit labels.

2. **`constant()` doesn't take ROM addresses.** Constants are symbolic values and should NOT have their values transformed by address maps.

3. **The ROM is exactly 8192 bytes** and mapped at &E000-&FFFF. This is the complete 6502 address space's top 8 KB — hardware vectors &FFFA-&FFFF are the last six bytes of the ROM.

4. **The bridge is not a BBC Micro.** There is no MOS, no OSBYTE/OSWORD, no sideways ROM paging. The bridge has its own 6502 and its own hardware (ADLC Econet controller chips, likely at I/O pages).


## Cross-ROM code similarity

The `find-shared` subcommand compares the Econet Bridge ROM against one
or more reference ROMs using opcode-sequence matching. This is useful
for detecting utility routines borrowed from (or between) other 6502
firmware such as Acorn NFS, ANFS, ADFS, the Tube Client, or the BBC
Micro MOS.

Invoke it directly with `[label=]path@load-addr` specs:

```sh
uv run acorn-econet-bridge-disasm-tool find-shared 1 \
    "nfs-3.34=../acorn-nfs/versions/nfs-3.34/rom/nfs-3.34.rom@&8000" \
    --min-len 8
```

The `tools/find_shared_with_siblings.py` wrapper runs the comparison
against every ROM it can find in the sibling acornaeology repos
(acorn-nfs, acorn-adfs, acorn-6502-tube-client) plus, if built, a
local OS 1.20 binary:

```sh
uv run tools/find_shared_with_siblings.py --min-len 8 --limit 8
```

### How the matcher works

For each ROM the tool does a linear opcode sweep (length-aware, using
the 6502 opcode table in `src/disasm_tools/mos6502.py`), then runs
Python's `difflib.SequenceMatcher` on the opcode-only streams. Matches
of `--min-len` or more consecutive instructions are reported with the
offset and runtime address in each ROM.

A trivial-span filter rejects matches with fewer than three distinct
opcodes, so padding regions (&FF/&00 fill) and degenerate sequences
like `RTS + 75 bytes of padding` do not appear in the output.

The matcher only looks at opcode bytes, not operands. `LDA &1234` and
`LDA &5678` are treated as identical, which is usually what you want:
it lets you spot the same routine moved to a different address or
touching different workspace variables.

### Maintaining the shared-code map

Findings from `find-shared` are persisted in `shared-code.json` at the
repo root, and rendered as `docs/SHARED-CODE.md` for browsing.
Curated human notes attach to the JSON.

**Refresh the scan** (run whenever a new sibling ROM appears, or an
existing sibling is re-annotated — labels moving can shift the
matcher's view):

```sh
uv run tools/refresh_shared_code.py
```

Refresh policy:

- Regions keyed on the Bridge primary address.
- For each region found by the latest scan: `peers` list is replaced
  and `primary_instructions`/`primary_bytes` are updated to the
  maximum observed. The curated `name` and `notes` fields are
  preserved.
- Regions not in the latest scan are kept in the JSON with a `stale:
  true` flag. The notes remain as archive; remove the entry manually
  if the region is genuinely gone.
- New regions get `name` and `notes` set to null for curation.

**Render the Markdown view:**

```sh
uv run tools/render_shared_code.py          # write docs/SHARED-CODE.md
uv run tools/render_shared_code.py --check  # pre-commit safety check
```

The pre-commit hook fails if the rendered `docs/SHARED-CODE.md` is
out of date with respect to `shared-code.json`, preventing drift
between the authoritative JSON and the human-readable view.

**Curation workflow:** When annotation work identifies what a shared
region actually does, edit `shared-code.json` to fill in the `name`
(a short identifier, ideally matching the sibling ROM's existing
label) and `notes` (one or two sentences on behaviour and why it's
shared). Re-run the render script and commit both files together.

Two adjacent regions (e.g. `&E3EF` and `&E3F0` in the initial scan)
are often the same routine observed with slightly different opcode
alignments across peer versions. Merge them manually by editing the
JSON: move the peers from one entry into the other and delete the
now-empty region. The matcher can't tell these apart on its own.


### Including BBC Micro OS 1.20

The only surviving high-quality source for OS 1.20 is Toby Nelson's
ACME-syntax reassembly at `/Users/rjs/Code/os120`. Build it to a
binary first:

```sh
brew install acme            # once
cd /Users/rjs/Code/os120
acme -o os120.bin os120_acme.a
```

The resulting `os120.bin` is byte-identical to the original OS 1.20
ROM (expected MD5 `0a59a5ba15fe8557b5f7fee32bbd393a`). Once built,
`find_shared_with_siblings.py` will pick it up automatically.

If you prefer to compare against a single target manually:

```sh
uv run acorn-econet-bridge-disasm-tool find-shared 1 \
    "mos-1.20=/Users/rjs/Code/os120/os120.bin@&C000" \
    --min-len 8
```


## Tools reference

| Tool | Source | Purpose |
|------|--------|---------|
| CLI entry point | `src/disasm_tools/cli.py` | Dispatches all subcommands |
| Verify | `src/disasm_tools/verify.py` | beebasm reassembly and byte comparison |
| Lint | `src/disasm_tools/lint.py` | Validate annotation addresses and doc links |
| Compare | `src/disasm_tools/compare.py` | Binary comparison with SequenceMatcher |
| Extract | `src/disasm_tools/asm_extract.py` | Extract assembly sections by address or label |
| Audit | `src/disasm_tools/audit.py` | Subroutine annotation audit |
| CFG | `src/disasm_tools/cfg.py` | Inter-procedural call graph |
| Context | `src/disasm_tools/context.py` | Per-subroutine commenting workspaces |
| Labels | `src/disasm_tools/labels.py` | Per-label renaming workspaces |
| Promote | `src/disasm_tools/promote.py` | Identify candidate entry points/subroutines |
| Backfill | `src/disasm_tools/backfill.py` | Propagate annotations between versions |
| Opcode tables | `src/disasm_tools/mos6502.py` | 6502 instruction lengths |
| Find shared code | `src/disasm_tools/find_shared.py` | Cross-ROM opcode-sequence similarity |
| Find shared (siblings) | `tools/find_shared_with_siblings.py` | Wrapper that preloads sibling-repo ROMs |
| Refresh shared-code map | `tools/refresh_shared_code.py` | Scan siblings + merge into `shared-code.json`, preserving curated notes |
| Render shared-code map | `tools/render_shared_code.py` | Render `shared-code.json` as `docs/SHARED-CODE.md` |
