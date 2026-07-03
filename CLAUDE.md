# CLAUDE.md

This file provides guidance when working with code in this repository.

## Project overview

Annotated disassembly of the Acorn Econet Bridge ROM — the firmware for the standalone 6502-based device that joins two Econet networks. Python scripts drive [dasmos](https://github.com/acornaeology/dasmos) (a programmable 6502 disassembler) to produce readable, verified assembly output from the original ROM binary. The first version covered is 1.

## Build commands

Requires [uv](https://docs.astral.sh/uv/) and [beebasm](https://github.com/stardot/beebasm) (v1.10+).

```sh
uv sync                                            # Install dependencies (incl. fantasm)
uv run python versions/econet-bridge-variant_1/disassemble/disasm_econet_bridge_variant_1.py  # Generate .asm and .json from ROM via dasmos
uv run fantasm lint variant_1 versions/econet-bridge-variant_1/disassemble/disasm_econet_bridge_variant_1.py  # Validate annotation addresses
uv run fantasm verify variant_1                    # Reassemble and byte-compare against original ROM
```

Verification is the primary correctness check: the generated assembly must reassemble to a byte-identical copy of the original ROM. Lint validates that all annotation addresses (comments, subroutines, labels) reference valid item addresses in the dasmos output. CI runs disassemble, lint, then verify on every push.

## Architecture

### Tooling: fantasm + dasmos

The disassembly tooling is provided by [fantasm](https://github.com/acornaeology/fantasm) — installed as a regular project dependency. fantasm exposes a `fantasm` CLI (subcommands: `verify`, `lint`, `compare`, `audit`, `cfg`, `comments`, `labels`, `context`, `asm`, `sub`, `addresses`, `annotations`, `backfill`, `promote`, `fingerprint`, `shared`, `info`, `project`, `disassemble`) and a `fantasm.api` package for programmatic use. Project layout, prefixes, and per-version metadata live in `fantasm.toml`. fantasm is library-agnostic: it runs the per-version driver script as a subprocess and consumes its `.asm` / `.json` output, so the dasmos migration was transparent to fantasm.

**Full fantasm reference: <https://acornaeology.github.io/fantasm/>** — the user guide covers every subcommand, the `fantasm.toml` schema, the version-graph workflows, and the importable `fantasm.api`. Reach for it before guessing.

[dasmos](https://github.com/acornaeology/dasmos) (a programmable 6502 disassembler with a stable 2.0 API, byte-faithful round-trip oracle, and Stevedore-managed CPU / renderer / environment plug-ins) is invoked directly via the per-version driver script under `versions/econet-bridge-<VER>/disassemble/`; fantasm operates on the `.asm` / `.json` artefacts dasmos emits. **dasmos driver-API guide: <https://acornaeology.github.io/dasmos/driver_api.html>** — read this before non-trivial driver edits. Local dasmos checkout for source-of-truth lookups: `/Users/rjs/Code/acornaeology/dasmos/` (sibling repo).

The project was originally written against [py8dis](https://github.com/acornaeology/py8dis) and migrated to dasmos in 2026; py8dis is no longer a dependency. If you ever need to re-port a fresh py8dis driver, the AST translator at `/Users/rjs/Code/acornaeology/dasmos/scripts/py8dis2dasmos.py` does it as a one-shot.

### Disassembly driver

`versions/econet-bridge-variant_1/disassemble/disasm_econet_bridge_variant_1.py` — the main annotation file. Configures a `dasmos.Disassembler` with labels, constants, subroutine descriptions, comments, and relocated code blocks using dasmos's API (`d.label()`, `d.comment()`, `d.subroutine()`, `d.entry()`, `d.add_move()`, `d.hook_subroutine()`, `d.format_hint()`). This is where most development work happens. Output is produced by `ir = d.disassemble(); ir.render('beebasm' | 'json')`.

**Indexed-base labels (dasmos 2.0).** dasmos now classifies each cross-reference as a *direct* access or an *indexing base* (`lda base,X`, where the byte touched is `base+X` and the base itself is never read/written), and surfaces the split in the xref prose ("used as index base N times") and in the structured JSON `references` entries. For an address touched **only** as an indexing base, use `d.index_base(addr, name, description=…, group=…, length=…)` instead of `d.label()`: it keeps the name/description/group so the `,X` operand still resolves and stays documented, but tags it `access='indexed_base'` and lists it under the JSON `index_bases` section rather than `memory_map` (it does not own that fixed byte). For a cluster of bases around a named anchor reached with small displacements, use `d.index_region(anchor, name, window=(lo, hi), …)` so neighbours render as `anchor±k,X`. The two 256-byte routing tables `reachable_via_a`/`reachable_via_b` are declared this way. A genuine code entry point reached via a vector (e.g. `.reset` at &E000, read as `lda &e000,X` by the self-test checksum loop) stays a normal code label — `index_base` is for data bases only. To find candidates after regenerating, grep the `.asm` for `used as index base` lines that do **not** also say `referenced`.

### Lint

`fantasm lint <VER> <DRIVER_PATH>` validates that every `comment()`, `subroutine()`, and `label()` address in a driver script corresponds to a valid address in the dasmos JSON output. (Doc-link checks against `rom.json`'s `address_links` / `glossary_links` aren't yet covered by fantasm; they'll need to come back as a project-specific tool or a fantasm contribution.)

### Verification

`fantasm verify <VER>` assembles the generated `.asm` with beebasm and does a byte-for-byte comparison against the original ROM.

### Version layout

Each ROM version lives under `versions/econet-bridge-<version>/`. Subdirectories:
- `rom/` — original ROM binary and metadata (`rom.json` with hashes)
- `disassemble/` — dasmos driver script
- `output/` — generated assembly (`.asm`) and structured data (`.json`)

Version IDs identify a specific board variant: the first is `variant_1`. (Two ROM variants are known to exist in the wild; the relationship between them hasn't been established, and neither carries a version number inside the image itself, so we label them by discovery order rather than by any embedded version or model number.) The directory layout is governed by `[versions] prefixes` in `fantasm.toml`; fantasm's `resolve_version_files()` maps a version ID to the matching `versions/econet-bridge-{version_id}/` directory.

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
- dasmos is a regular PyPI dependency (`dasmos>=2.0.1`); the local source-of-truth checkout lives at `/Users/rjs/Code/acornaeology/dasmos/`
- Assembly output targets beebasm syntax
- Assembly comments are formatted to fit within 62 characters

### Hardware map (from schematic and code inspection)

- Two MC6854 ADLCs: one at &C800-&C803 (`adlc_a_*`), one at &D800-&D803 (`adlc_b_*`). ~IRQ outputs are **not** wired to the 6502 ~IRQ line — all ADLC attention is polled via SR1.
- Two banks of jumpered station-number links, each buffered by a 74LS244: station_id_a at &C000 (read-only), station_id_b at &D000.
- 6502 ~IRQ line carries a **single push-button** that enters the self-test at the IRQ/BRK vector target &F000. Do not press while connected to a live network.
- **Independent cross-reference.** J.G. Harston's [BRIDGE.SRC](https://mdfs.net/System/ROMs/Econet/Bridge/BRIDGE.SRC) is another analyst's BBC-BASIC-embedded disassembly of the same binary variant. His code assembles to the same addresses as our annotations, which makes him a useful second opinion. JGH is a fellow reverse-engineer working from the same ROM, so where his reading and ours differ we weigh each against the evidence. His protocol-level names (BridgeReset / BridgeReply / WhatNet / IsNet / BridgeQuery port) are adopted where they describe a conclusion we have independently verified; where he annotates a field we haven't yet understood, we note his interpretation and keep it tentative. Refinements informed by his source are paraphrased rather than copied verbatim.
- **Status LED on ADLC B.** The ~LOC/DTR pin of IC18 (the ADLC at &D800 — `adlc_b`) is wired to the **anode** of the front-panel LED, with the cathode going to ground via a current-limiting resistor (per Ian Stocks's schematic and Chris Oddy's replica). The equivalent pin on IC12 (`adlc_a` at &C800) is not connected. On the MC6854, ~LOC/DTR is driven by CR3 bit 7 in non-loop mode **with inverted polarity** — the datasheet states "when the LOC/DTR control bit is high the DTR output will be low". Combined with the anode-to-pin wiring this means **CR3 bit 7 = 0 → pin HIGH → LED LIT**, and **CR3 bit 7 = 1 → pin LOW → LED DARK**. The firmware therefore *lights* the LED in normal operation (`adlc_b_full_reset` writes `CR3 = &00`) and *extinguishes* it when entering self-test (`self_test_reset_adlcs` at &F005 writes `CR3 = &80`). The visible self-test flash is not driven by an explicit toggle — it emerges because the loopback tests' `CR1 = &C0` full-reset clears CR3 bit 7 mid-pass, lighting the LED again, and the alternate-pass path at &F26F deliberately skips the re-extinguish step. See `docs/analysis/led-self-test-indicator.md` for the full mechanism.

### dasmos configuration

The bridge is **not** a BBC Micro. The driver constructs `dasmos.Disassembler.create(cpu='6502', ...)` with **no** BBC environment plug-ins — that is, do **not** add any of these to the `environments=[...]` argument:

- `acorn_mos` — would install OSBYTE, OSWRCH, OSNEWL and other MOS entry points at &FF00-&FFFF
- `acorn_model_b_hardware` / `acorn_master_hardware` — would install labels for SHEILA I/O at &FE00-&FEFF
- `acorn_sideways_rom` — would add sideways-ROM header handling
- `acorn_fdc_1770` / `acorn_fdc_8271` — disc-controller register labels

The bridge has its own hardware (two MC6854 ADLCs at &C800-&C803 and &D800-&D803, station-ID buffers at &C000 and &D000) and no MOS. All labels must be added by hand based on what the bridge ROM actually does.
