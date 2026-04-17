# Acorn Econet Bridge

[![Verify disassembly](https://github.com/acornaeology/acorn-econet-bridge/actions/workflows/verify.yml/badge.svg)](https://github.com/acornaeology/acorn-econet-bridge/actions/workflows/verify.yml)

The Acorn Econet Bridge is a standalone 6502-based device that joins two Econet networks, forwarding traffic between them while isolating local traffic to each side. The bridge firmware lives in an 8 KB ROM at &E000-&FFFF and implements the bridge protocols that allow file servers, printer servers, and station clients on different Econet segments to communicate.

This repository contains annotated disassemblies of the Acorn Econet Bridge ROM, produced by reverse-engineering the original 6502 machine code. Each disassembly includes named labels, comments explaining the logic, and cross-references between subroutines.

## Versions

- **Acorn Econet Bridge 1**
  - [Formatted disassembly on acornaeology.uk](https://acornaeology.uk/acorn-econet-bridge/1.html)
  - [Disassembly source on GitHub](https://github.com/acornaeology/acorn-econet-bridge/blob/master/versions/econet-bridge-1/output/econet-bridge-1.asm)
  - [Acorn Econet Bridge in The BBC Micro ROM Library](https://tobylobster.github.io/rom_library/?md5=d5328f517902a4d2659e302acfc0882f)

## How it works

The disassembly is produced by a Python script that drives a custom version of [py8dis](https://github.com/acornaeology/py8dis), a programmable disassembler for 6502 binaries. The script feeds the original ROM image to py8dis along with annotations — entry points, labels, constants, and comments — to produce readable assembly output.

The output is verified by reassembling with [beebasm](https://github.com/stardot/beebasm) and comparing the result byte-for-byte against the original ROM. This round-trip verification runs automatically in CI on every push.

## Disassembling locally

Requires [uv](https://docs.astral.sh/uv/) and [beebasm](https://github.com/stardot/beebasm) (v1.10+).

```sh
uv sync
uv run acorn-econet-bridge-disasm-tool disassemble 1
uv run acorn-econet-bridge-disasm-tool verify 1
```

## (Re-)Assembling locally

To assemble the `.asm` file back into a ROM image using [beebasm](https://github.com/stardot/beebasm):

```sh
beebasm -i versions/econet-bridge-1/output/econet-bridge-1.asm -o econet-bridge-1.rom
```

## Analyses

Writeups of interesting details uncovered during the disassembly work.

- [Acorn Econet Bridge — architecture overview](docs/analysis/bridge-architecture-overview.md)
  Top-down tour of the whole firmware assembled from the annotated disassembly. Covers the hardware, the boot sequence, steady-state operation, the bridge-announce/query protocol, forwarding via the four-way handshake, and self-test. Serves as the entry point that ties the other writeups together.
- [Anti-aliasing in the Econet Bridge's RAM test](docs/analysis/ram-test-anti-aliasing.md)
  A close reading of the thirteen-instruction routine at &E00B that sizes the Bridge's RAM. The INC $00 instructions between each write and read are a layered defence against three distinct failure modes.
- [The self-test LED, driven by a repurposed ADLC pin](docs/analysis/led-self-test-indicator.md)
  How the Bridge's single front-panel LED is driven by CR3 bit 7 on ADLC B, with exactly two writes in the whole ROM, making it a pure function of which init path was taken.
- [Escape-to-main: the Bridge's cooperative error-recovery idiom](docs/analysis/escape-to-main-control-flow.md)
  Four routines share a PLA/PLA/JMP main_loop abnormal exit that drops the caller's return address and collapses any failed operation back to the main dispatcher. Trades per-site clarity for global simplicity and a meaningful ROM-space saving.
- [One frame, two broadcasts: reset-time announcement](docs/analysis/two-broadcasts-one-template.md)
  The Bridge announces itself on both Econet sides at power-on by building a single frame template and transmitting it twice, patching a single byte of payload between the two transmissions. A small idiom with a clean separation of concerns between builder and transmitter.
- [The Econet Bridge has no station address](docs/analysis/bridge-has-no-station-number.md)
  Architectural writeup on why the Bridge operates without a station number on either of its connected networks. Evidence from the board's two 74LS244 network-number buffers, the firmware's network-keyed routing tables, and the Installation Guide. Covers the &18 firmware marker in outbound announcements and the practical implications for anyone reading the disassembly.
- [Bridging the four-way handshake](docs/analysis/four-way-handshake-bridging.md)
  How the Bridge forwards Econet's four-stage scout/ACK/data/ACK transactions across two segments. Documents the receive-and-stage pattern that makes rx_a_forward's puzzling A-B-A transmit tail resolve into a clean protocol implementation, and the role of escape-to-main in making mid-handshake failures safe without any per-transaction state.
- [Event-driven re-announcement: why a solo Bridge goes silent](docs/analysis/event-driven-reannouncement.md)
  A full-ROM audit of every write to announce_flag shows that bridge re-announcement is purely reactive: only receiving a BridgeReset from another bridge triggers a burst, and BridgeReply frames deliberately don't cascade. A bridge with no peers emits two frames in its lifetime and then stays silent forever — by design, not by bug.

## References

- [Econet Installation Guide (0482,009 Issue 1, 27 September 1988) (PDF)](https://www.theoddys.com/acorn/acorn_system_filing_systems/econet/documentation/Econet%20Installation%20Guide%200482%2C009%20Issue%201%2027%20September%201988.pdf)
  Acorn's official Econet installation guide. Chapter 3 covers the Bridge. A local copy is kept in docs/.
- [The Replica Acorn Econet Bridge project](https://www.theoddys.com/acorn/acorn_replica_boards/replica_acorn_econet_bridge/replica_acorn_econet_bridge.html)
  A modern reproduction of the Acorn Econet Bridge, with useful photographs and build notes.
- [Replica Econet Bridge Schematic (PDF)](https://www.theoddys.com/acorn/acorn_replica_boards/replica_acorn_econet_bridge/Replica%20Econet%20Bridge%20Schematic.pdf)
  Schematic for the replica board, closely matching the original Acorn design.
- [Ian Stocks's reverse-engineered Acorn Econet Bridge schematic (PDF)](docs/econet_bridge_Ian_Stocks.pdf)
  Schematic reverse-engineered from an original Acorn board. Local copy in docs/; originally shared in the Stardot forum thread below.
- [Stardot Forums: Econet Bridge schematic thread](https://stardot.org.uk/forums/viewtopic.php?t=12324)
  Discussion of Ian Stocks's reverse-engineered schematic and Bridge hardware details.
- [Stardot Forums: discussion of the Acorn Econet Bridge ROM](https://stardot.org.uk/forums/viewtopic.php?t=8696)
  Thread discussing the Bridge ROM's behaviour and internals.
- [Rick Murray's notes on the Acorn Econet Bridge](https://heyrick.eu/econet/bridge/acorn.html)
  Overview of the Acorn Econet Bridge hardware, firmware behaviour, and configuration.
- [Beebmaster: The Acorn Bridge](https://www.beebmaster.co.uk/Econet/AcornBridge.html)
  Beebmaster's page on the Acorn Bridge, with photographs, configuration notes, and operational details.
- [J.G. Harston's mdfs.net Econet Bridge archive](https://mdfs.net/System/ROMs/Econet/Bridge/)
  Directory listing for the Acorn Econet Bridge on mdfs.net.
- [J.G. Harston's Bridge disassembly (BBC BASIC embedded-assembler source)](https://mdfs.net/System/ROMs/Econet/Bridge/BRIDGE.SRC)
  A parallel disassembly of the same binary variant using BBC BASIC's inline assembler, with memory-layout comments and protocol-level terminology (BridgeReset / BridgeReply / WhatNet / IsNet / BridgeQuery port). Useful as a second reading, though JGH is another reverse-engineer rather than an authoritative source -- his comments are paraphrased rather than quoted, and weighed against our own analysis.
- [Motorola MC68B54P ADLC datasheet (PDF)](docs/Motorola-MC68B54P-datasheet.pdf)
  Datasheet for the Advanced Data Link Controller used on each Econet port of the Bridge. Authoritative reference for CR1-CR4 and SR1/SR2 bit meanings.

## Credits

- [py8dis](https://github.com/acornaeology/py8dis) by [SteveF](https://github.com/ZornsLemma), forked for use with acornaeology
- [beebasm](https://github.com/stardot/beebasm) by Rich Mayfield and contributors
- [The BBC Micro ROM Library](https://tobylobster.github.io/rom_library/) by tobylobster

## License

The annotations and disassembly scripts in this repository are released under the [MIT License](LICENSE). The original ROM images remain the property of their respective copyright holders.
