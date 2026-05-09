# Disassembly Guide

How to produce annotated, verified disassemblies of the Acorn Econet Bridge ROM.

For project overview and build instructions, see [README.md](README.md). For architecture details, see [CLAUDE.md](CLAUDE.md). For terminology, see [GLOSSARY.md](GLOSSARY.md).


## Prerequisites

- [uv](https://docs.astral.sh/uv/) for Python dependency management
- [beebasm](https://github.com/stardot/beebasm) (v1.10+) for assembly verification
- The ROM binary (8192 bytes) for the version being disassembled
- MD5 and SHA-256 hashes of the ROM (`md5 <rom>`, `shasum -a 256 <rom>`)


## Quick reference: CLI tools

The disassembly tooling is provided by [fantasm](https://acornaeology.github.io/fantasm/), invoked as `uv run fantasm <command>`. The full command-by-command reference is at <https://acornaeology.github.io/fantasm/cli.html> and the workflow guide at <https://acornaeology.github.io/fantasm/workflows.html>; the most-used commands here are:

| Command | Description | Example |
|---------|-------------|---------|
| `disassemble` | Run the dasmos driver to generate `.asm` and `.json` | `fantasm disassemble variant_1` |
| `verify` | Reassemble and byte-compare against original ROM | `fantasm verify variant_1` |
| `lint` | Validate annotation addresses against the disassembly | `fantasm lint variant_1 versions/econet-bridge-variant_1/disassemble/disasm_econet_bridge_variant_1.py` |
| `compare` | Compare two ROM versions (byte and opcode level) | `fantasm compare a b` |
| `asm extract` | Extract assembly section by address range or label | `fantasm asm extract variant_1 &E000 &E040` |
| `audit summary/detail/undeclared` | Subroutine annotation audit | `fantasm audit summary variant_1` |
| `cfg leaves/roots/depth/sub/blocks/sub-context` | Inter-procedural call graph queries | `fantasm cfg depth variant_1` |
| `context uncommented` | Find subroutines with low comment density | `fantasm context uncommented variant_1` |
| `labels classify/apply` | Auto-label classification + rename application | `fantasm labels classify variant_1` |
| `sub insert` | Find insertion point for a new `subroutine()` | `fantasm sub insert <driver> &E000` |
| `comments suggest/check` | Comment suggestions and consistency checks | `fantasm comments check variant_1` |
| `backfill` / `annotations diff` | Cross-version annotation propagation and diff | `fantasm backfill a b` |
| `promote` | Find labels that should be promoted to entry points | `fantasm promote variant_1` |
| `shared` | Find shared 6502 code fragments vs. reference ROMs | `fantasm shared <primary> nfs=path@&8000` |
| `addresses map` | Map source addresses to a target ROM | `fantasm addresses map a b --addr 0xE000` |

`fantasm` accepts hex addresses in multiple formats (`&E000`, `$E000`, `0xE000`) as well as label names where appropriate.


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
uv run python versions/econet-bridge-<VER>/disassemble/disasm_econet_bridge_<VER>.py
uv run fantasm verify <VER>
```

Fix errors until verification passes, then annotate.


## dasmos driver script reference

The driver script configures a `dasmos.Disassembler` instance. Each call annotates the disassembly output. The full driver-API guide lives at <https://acornaeology.github.io/dasmos/driver_api.html> – read it before non-trivial driver edits.

### Bootstrap

```python
import dasmos
from dasmos import Align

d = dasmos.Disassembler.create(cpu="6502")  # no environments — bridge is not a BBC Micro
d.load(rom_filepath, 0xE000)
d.entry(0xFFFC)  # or follow vectors

# ... annotations ...

ir = d.disassemble()
asm_filepath.write_text(str(ir.render("beebasm")), encoding="utf-8")
json_filepath.write_text(str(ir.render("json")), encoding="utf-8")
```

### Core API calls

All calls are methods on the `Disassembler` instance (`d`).

**`d.label(address, name)`** — Assign a symbolic name to a ROM or RAM address. Also covers runtime-only addresses outside the ROM (no separate `external_label`).

**`d.constant(name, value)`** — Define a named constant for a numeric value. Used for hardware register addresses, protocol codes, etc. The value is symbolic, not a ROM address.

**`d.comment(address, text, align=Align.INLINE)`** — Attach a comment to a specific instruction address. `align` controls whether the comment renders inline or above the instruction.

**`d.subroutine(address, name, ...)`** — Mark the start of a subroutine with a title and description.

**`d.entry(address, name=...)`** — Mark an address as a code entry point.

**`d.add_move(dest, source, length)`** — Declare a relocated code block. Returns a typed `Move` handle that is also a context manager (`with move: d.label(...)` scopes annotations under it).

**`d.hook_subroutine(address, hook_fn)`** — Register a custom Python function for special handling of dispatch tables, inline data, etc. Bundled hooks (`stringhi_hook`, `stringz_hook`, `stringcr_hook`) live in `dasmos.hooks`.

**`d.format_hint(address, FormatHint.X)`** — Declare the operand-byte's semantic intent (CHAR / DECIMAL / HEX / BINARY / OCTAL / INKEY); each renderer chooses its syntax. Sugars: `d.char_literal(addr)`, `d.inkey_code(addr)`.

**`string_detection_min_length`** ctor kwarg / property — declarative replacement for the older `autostring(N)` post-trace step.


## Annotation guidelines

### Subroutine descriptions

A good subroutine description:

- **Title**: A standalone phrase or short sentence summarising the routine's purpose.
- **Description**: Explains behaviour, entry/exit conditions, and side effects.
- **Calling convention**: Uses `On entry:` and `On exit:` blocks with indented register/flag details.

### Comment length

Assembly comments are formatted to fit within 62 characters (legacy formatting constraint inherited from the py8dis-era driver, preserved by the `byte_column_format='py8dis'` renderer flag).

### Hex notation

- Use **Acorn notation** (`&XXXX`) in documentation, Markdown files, and human-readable output
- Use **Python notation** (`0xXXXX`) in Python scripts (driver scripts, tools)


## Key gotchas

1. **Auto-labels can collide.** Any `return_N`, `loop_cXXXX`, etc. that the disassembler synthesises in both main ROM and relocated code will cause beebasm duplicate label errors. Fix by adding explicit labels.

2. **`constant()` doesn't take ROM addresses.** Constants are symbolic values and should NOT have their values transformed by address maps.

3. **The ROM is exactly 8192 bytes** and mapped at &E000-&FFFF. This is the complete 6502 address space's top 8 KB — hardware vectors &FFFA-&FFFF are the last six bytes of the ROM.

4. **The bridge is not a BBC Micro.** There is no MOS, no OSBYTE/OSWORD, no sideways ROM paging. The bridge has its own 6502 and its own hardware (ADLC Econet controller chips, likely at I/O pages).


## Cross-ROM code similarity

The `fantasm shared` subcommand compares the Econet Bridge ROM against
one or more reference ROMs using opcode-sequence matching. This is
useful for detecting utility routines borrowed from (or between) other
6502 firmware such as Acorn NFS, ANFS, ADFS, the Tube Client, or the
BBC Micro MOS.

Invoke it with `[label=]path@load-addr` specs (the primary spec
identifies the Bridge ROM, then any number of references):

```sh
uv run fantasm shared \
    "bridge=versions/econet-bridge-variant_1/rom/econet-bridge-variant_1.rom@&E000" \
    "nfs-3.34=../acorn-nfs/versions/nfs-3.34/rom/nfs-3.34.rom@&8000" \
    --min-len 8
```

A multi-sibling sweep (formerly `tools/find_shared_with_siblings.py`)
is now an ad-hoc invocation of `fantasm shared` against the sibling
ROMs you want to compare; the curated map at `shared-code.json` plus
`tools/render_shared_code.py` remain the project's record of what's
shared and what each match means.

### How the matcher works

For each ROM the tool does a linear opcode sweep (length-aware, using
the 6502 opcode table in `fantasm.api.mos6502`), then runs Python's
`difflib.SequenceMatcher` on the opcode-only streams. Matches of
`--min-len` or more consecutive instructions are reported with the
offset and runtime address in each ROM.

A trivial-span filter rejects matches with fewer than three distinct
opcodes, so padding regions (&FF/&00 fill) and degenerate sequences
like `RTS + 75 bytes of padding` do not appear in the output.

The matcher only looks at opcode bytes, not operands. `LDA &1234` and
`LDA &5678` are treated as identical, which is usually what you want:
it lets you spot the same routine moved to a different address or
touching different workspace variables.

### Maintaining the shared-code map

Findings from `fantasm shared` are persisted in `shared-code.json` at
the repo root, and rendered as `docs/SHARED-CODE.md` for browsing.
Curated human notes attach to the JSON.

The previous `tools/refresh_shared_code.py` wrapper has been retired
along with `disasm_tools/`. To refresh the JSON after a sibling ROM
changes: run `fantasm shared` against the relevant siblings, capture
the output as TSV (`--as tsv`), and merge into `shared-code.json` by
hand (preserving the curated `name`/`notes`). A more polished
refresh wrapper can return if it earns its keep.

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
uv run fantasm shared \
    "bridge=versions/econet-bridge-variant_1/rom/econet-bridge-variant_1.rom@&E000" \
    "mos-1.20=/Users/rjs/Code/os120/os120.bin@&C000" \
    --min-len 8
```


## Tools reference

The disassembly toolchain itself lives in [fantasm](https://acornaeology.github.io/fantasm/) — see [the published docs](https://acornaeology.github.io/fantasm/) for module-level details. The repo-local tools that remain are:

| Tool | Source | Purpose |
|------|--------|---------|
| Render shared-code map | `tools/render_shared_code.py` | Render `shared-code.json` as `docs/SHARED-CODE.md` |
| README generator | `generate_readme.py` | Render `README.md` from `acornaeology.json` and `README.md.j2` |
