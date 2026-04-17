# Shared code regions

This document catalogues regions of the Econet Bridge ROM (`econet-bridge-1`, loaded at `&E000`) whose opcode sequences also appear in other Acorn 6502 ROMs, as detected by `tools/refresh_shared_code.py`.

Matching compares opcode bytes only, ignoring operands, so the same routine at a different address in the peer ROM (or touching different workspace variables) is still matched. The trivial-span filter rejects matches with fewer than 3 distinct opcodes to suppress false positives from padding regions.

Regions are listed in descending order of peer count — the most widely shared routines (likely the oldest and most foundational) appear first. The Bridge primary addresses link into the disassembly output; peer addresses into the relevant sibling repository's disassembly output.

## Scan metadata

- **Last refreshed:** 2026-04-17
- **Minimum match length:** 8 instructions
- **Trivial-span floor:** 3 distinct opcodes
- **References scanned:** `anfs-4.08.53`, `anfs-4.18`, `nfs-3.34`, `nfs-3.34B`, `nfs-3.35D`, `nfs-3.35K`, `nfs-3.40`, `nfs-3.60`, `nfs-3.62`, `nfs-3.65`, `tube-6502-client-1.10`, `adfs-1.30`, `mos-1.20`

## Active regions (8)

### `&E3EF` — adlc_a_full_reset (alternate alignment) — 13 instr, 29 bytes

Same routine as &E3F0 — the Bridge subroutine actually starts at &E3F0 (called from the reset vector at &E005). The matcher picks an alignment one byte earlier for these peers because the RTS at &E3EF happens to match the preceding byte in those NFS versions. See &E3F0 for the port of NFS's `adlc_full_reset` description.

| ROM | Address | Instructions | Bytes |
|-----|---------|-------------:|------:|
| `anfs-4.08.53` | `&895E` | 12 | 27 |
| `anfs-4.18` | `&8968` | 12 | 27 |
| `nfs-3.34` | `&96DB` | 13 | 29 |
| `nfs-3.34B` | `&96DB` | 13 | 29 |
| `nfs-3.60` | `&9F3C` | 12 | 27 |
| `nfs-3.62` | `&9F3C` | 12 | 27 |
| `nfs-3.65` | `&9F6F` | 12 | 27 |

### `&E120` — (unnamed) — 10 instr, 25 bytes

Matches code in ANFS and NFS 3.60+ that is variously labelled `scout_complete` (NFS 3.60/3.62) and `accept_scout_net` (NFS 3.35D). The shared fragment may be an Econet frame-handling pattern rather than a verbatim routine. Worth revisiting once the Bridge's frame processing is annotated.

| ROM | Address | Instructions | Bytes |
|-----|---------|-------------:|------:|
| `anfs-4.08.53` | `&812C` | 10 | 25 |
| `anfs-4.18` | `&8137` | 10 | 25 |
| `nfs-3.60` | `&9738` | 10 | 25 |
| `nfs-3.62` | `&9738` | 10 | 25 |
| `nfs-3.65` | `&9758` | 10 | 25 |

### `&E2A1` — (unnamed) — 8 instr, 19 bytes

NFS 3.60+ annotates the peer as `CR1=&00: disable all interrupts`; NFS 3.34 annotates the same opcode sequence as `C=1: past max handles, done`. The 8-instruction match likely reflects a common `LDA #0 / STA cr1 / ...` ADLC-shutdown pattern rather than a shared routine. Confirm once the Bridge routine at &E2A1 is analysed.

| ROM | Address | Instructions | Bytes |
|-----|---------|-------------:|------:|
| `anfs-4.08.53` | `&82B9` | 8 | 19 |
| `anfs-4.18` | `&82C4` | 8 | 19 |
| `nfs-3.60` | `&98C3` | 8 | 19 |
| `nfs-3.62` | `&98C3` | 8 | 19 |
| `nfs-3.65` | `&98E5` | 8 | 19 |

### `&E5B3` — (unnamed) — 10 instr, 25 bytes

Matches NFS 3.34-3.35K only (not ANFS or later NFS). NFS peer at &976E has an inline comment `SR2 = 0 -- RTI, wait for next NMI` indicating ADLC status-polling code inside the NMI handler. On the Bridge the equivalent is polled rather than NMI-driven (see wait_adlc_*_irq), so the Bridge routine may be a polled version of the same idea.

| ROM | Address | Instructions | Bytes |
|-----|---------|-------------:|------:|
| `nfs-3.34` | `&976E` | 10 | 25 |
| `nfs-3.34B` | `&976E` | 10 | 25 |
| `nfs-3.35D` | `&9778` | 10 | 25 |
| `nfs-3.35K` | `&9778` | 10 | 25 |

### `&E644` — (unnamed) — 9 instr, 22 bytes

Peer in NFS 3.34-3.35K is labelled `data_rx_tube_error` (Tube data-frame error). The Bridge has no Tube, so this is either coincidental opcode overlap on an error-path pattern, or the Bridge has an analogous RX-error handler that shares ADLC-reset prologue. Inspect during annotation of &E644.

| ROM | Address | Instructions | Bytes |
|-----|---------|-------------:|------:|
| `nfs-3.34` | `&9930` | 9 | 22 |
| `nfs-3.34B` | `&9930` | 9 | 22 |
| `nfs-3.35D` | `&993A` | 9 | 22 |
| `nfs-3.35K` | `&993A` | 9 | 22 |

### `&E3F0` — adlc_a_full_reset — 12 instr, 28 bytes

Aborts all ADLC A activity and returns it to idle RX listen mode: CR1=&C1 (reset TX+RX, AC=1), CR4=&1E (8-bit RX, abort extend, NRZ), CR3=&00 (normal, NRZ). Falls through to `adlc_a_listen` at &E3FF. Ported from NFS 3.34's `adlc_full_reset` at &96DC (same byte sequence). The ADLC B mirror at &E40A is not itself detected by the matcher because no peer ROM has an identical second-ADLC routine.

| ROM | Address | Instructions | Bytes |
|-----|---------|-------------:|------:|
| `nfs-3.35D` | `&96E6` | 12 | 28 |
| `nfs-3.35K` | `&96E6` | 12 | 28 |

### `&E47A` — (unnamed) — 8 instr, 18 bytes

Small 8-instruction match against an unrelated-looking region of ADFS 1.30 (only inline comment there is `Dead data: &0A`). Probably coincidental opcode-pattern overlap rather than deliberate code reuse. Flag if Bridge analysis shows this is part of a meaningful routine.

| ROM | Address | Instructions | Bytes |
|-----|---------|-------------:|------:|
| `adfs-1.30` | `&88E5` | 8 | 18 |

### `&F112` — (unnamed) — 8 instr, 19 bytes

Tiny 8-instruction match against ADFS 1.30 (peer annotation is just `Restore Y`). Almost certainly a coincidental match on a generic register-save/restore epilogue.

| ROM | Address | Instructions | Bytes |
|-----|---------|-------------:|------:|
| `adfs-1.30` | `&8C30` | 8 | 19 |
