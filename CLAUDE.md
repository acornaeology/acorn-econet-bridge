# CLAUDE.md

This file provides guidance when working with code in this repository.

## Project overview

Annotated disassembly of the Acorn Econet Bridge ROM — the firmware for the standalone 6502-based device that joins two Econet networks. Python scripts drive py8dis (a programmable 6502 disassembler) to produce readable, verified assembly output from the original ROM binary. The first version covered is 1.

## Build commands

Requires [uv](https://docs.astral.sh/uv/) and [beebasm](https://github.com/stardot/beebasm) (v1.10+).

```sh
uv sync                                            # Install dependencies
uv run acorn-econet-bridge-disasm-tool disassemble 1  # Generate .asm and .json from ROM
uv run acorn-econet-bridge-disasm-tool lint 1         # Validate annotation addresses
uv run acorn-econet-bridge-disasm-tool verify 1       # Reassemble and byte-compare against original ROM
```

Verification is the primary correctness check: the generated assembly must reassemble to a byte-identical copy of the original ROM. Lint validates that all annotation addresses (comments, subroutines, labels) reference valid item addresses in the py8dis output. CI runs `disassemble`, `lint`, then `verify` on every push.

## Architecture

### CLI entry point

`src/disasm_tools/cli.py` — subcommands: `disassemble`, `verify`, `lint`, `compare`, `extract`, `audit`, `cfg`, `context`, `labels`, `rename-labels`, `insert-point`, `comment-check`, `backfill`, `promote`. Sets env vars `ACORN_ECONET_BRIDGE_ROM` and `ACORN_ECONET_BRIDGE_OUTPUT` before invoking version-specific scripts.

### Disassembly driver

`versions/econet-bridge-1/disassemble/disasm_econet_bridge_1.py` — the main annotation file. Configures py8dis with labels, constants, subroutine descriptions, comments, and relocated code blocks using py8dis's DSL (`label()`, `constant()`, `comment()`, `subroutine()`, `move()`, `hook_subroutine()`). This is where most development work happens.

### Lint

`src/disasm_tools/lint.py` — validates that every `comment()`, `subroutine()`, and `label()` address in a driver script corresponds to a valid address in the py8dis JSON output. Also validates `address_links` and `glossary_links` in each version's `rom.json`.

### Verification

`src/disasm_tools/verify.py` — assembles the generated `.asm` with beebasm and does a byte-for-byte comparison against the original ROM.

### Version layout

Each ROM version lives under `versions/econet-bridge-<version>/`. Subdirectories:
- `rom/` — original ROM binary and metadata (`rom.json` with hashes)
- `disassemble/` — py8dis driver script
- `output/` — generated assembly (`.asm`) and structured data (`.json`)

Version IDs in `acornaeology.json` and CLI arguments are bare numbers (`1`). The `resolve_version_dirpath()` helper in `src/disasm_tools/paths.py` maps them to the directory using the `econet-bridge` prefix.

### Glossary

`GLOSSARY.md` — project-level glossary of Econet-specific and Acorn terms, registered in `acornaeology.json` as `"glossary": "GLOSSARY.md"`. Uses Markdown definition-list syntax with a brief/extended split:

```markdown
**TERM** (Expansion)
: Brief definition — one or two sentences. What the term IS.

  Extended detail — how the bridge uses it, implementation specifics,
  or additional context. Shown only on the glossary page.
```

First paragraph = brief (tooltip text). Subsequent indented paragraphs after a blank line = extended (glossary page only). Entries without extended detail keep a single paragraph.

### Documentation links in `rom.json`

Each version's `rom/rom.json` has an optional `docs` array. Each doc entry can have:

- `address_links` — maps hex address patterns in Markdown to disassembly addresses (validated by lint against the JSON output)
- `glossary_links` — maps term patterns in Markdown to glossary entries (validated by lint against `GLOSSARY.md`)

Both use the same shape: `{"pattern": "...", "occurrence": 0, "term"|"address": "..."}`. The `occurrence` field is a 0-based index among all substring matches of the pattern.

## Key technical context

- Econet Bridge ROM base address: 0xE000, size: 8192 bytes (8 KB, mapped at &E000-&FFFF on the bridge's 6502)
- The bridge is a standalone device, not a BBC Micro sideways ROM
- Reset vector (&FFFC/D) points into the ROM; IRQ/BRK vector (&FFFE/F) likewise
- NMOS 6502 processor (confirm during disassembly)
- py8dis dependency is a custom fork at `github.com/acornaeology/py8dis`
- Assembly output targets beebasm syntax
- Assembly comments are formatted to fit within 62 characters

### Hardware map (from schematic and code inspection)

- Two MC6854 ADLCs: one at &C800-&C803 (`adlc_a_*`), one at &D800-&D803 (`adlc_b_*`). ~IRQ outputs are **not** wired to the 6502 ~IRQ line — all ADLC attention is polled via SR1.
- Two 74LS244 buffers exposing soldered station-number links: station_id_a at &C000 (read-only), station_id_b at &D000.
- 6502 ~IRQ line carries a **single push-button** that enters the self-test at the IRQ/BRK vector target &F000. Do not press while connected to a live network.
- **Independent cross-reference.** J.G. Harston's [BRIDGE.SRC](https://mdfs.net/System/ROMs/Econet/Bridge/BRIDGE.SRC) is another analyst's BBC-BASIC-embedded disassembly of the same binary variant. His code assembles to the same addresses as our annotations, which makes him a useful second opinion. JGH is a fellow reverse-engineer working from the same ROM, so where his reading and ours differ we weigh each against the evidence. His protocol-level names (BridgeReset / BridgeReply / WhatNet / IsNet / BridgeQuery port) are adopted where they describe a conclusion we have independently verified; where he annotates a field we haven't yet understood, we note his interpretation and keep it tentative. Refinements informed by his source are paraphrased rather than copied verbatim.
- **Status LED on ADLC B.** The ~LOC/DTR pin of IC18 (the ADLC at &D800 — `adlc_b`) is wired to the low side of the front-panel LED (high side tied via a resistor to Vcc). The equivalent pin on IC12 (`adlc_a` at &C800) is not connected. On the MC6854, ~LOC/DTR is driven by CR3 bit 7 in non-loop mode **with inverted polarity** — the datasheet states "when the LOC/DTR control bit is high the DTR output will be low". So CR3 bit 7 = 1 sinks the pin low and lights the LED; CR3 bit 7 = 0 releases the pin and leaves the LED dark. The firmware lights the LED only inside `self_test_reset_adlcs` at &F005; any normal `adlc_b_full_reset` clears it.

### py8dis configuration

The bridge is **not** a BBC Micro. The driver script must not call any of py8dis's BBC-specific convenience helpers:

- `acorn.hardware(machine)` — would install labels for SHEILA I/O at &FE00-&FEFF
- `acorn.mos_labels()` — would install OSBYTE, OSWRCH, OSNEWL and other MOS entry points at &FF00-&FFFF
- `acorn.is_sideways_rom()` — would add sideways-ROM header handling
- `acorn.add_oswrsc()` etc. — MOS hooks

The bridge has its own hardware (ADLC Econet controllers at page-aligned I/O addresses — &C000 region seems likely from the initial disassembly) and no MOS. All labels must be added by hand based on what the bridge ROM actually does.
