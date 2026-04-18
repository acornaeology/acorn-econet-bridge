# Acorn Econet Bridge — architecture overview

This is a top-down description of how the Acorn Econet Bridge works, assembled from the annotated disassembly of its 8 KiB firmware. It's intended as the entry point for the other analysis documents in this directory: each idiom or subsystem described here is linked to a more detailed piece that goes into the implementation specifics.

The Bridge is a small, self-contained, piece of network infrastructure — it does one job, does it quietly, and was designed to be invisible to the users whose traffic passes through it. The firmware is correspondingly compact: 8 KiB of ROM runs the whole thing, on an independent 6502 CPU with 8 KiB of RAM for buffering. No operating system. No bootloader. No configuration interface. Just two Econet ports, two jumper-set network numbers, and a protocol that discovers the rest at runtime.


## What the Bridge does

At its simplest: an Econet network segment can span about 500 metres. Larger installations use multiple segments connected by bridges. Each bridge sits between two segments, listening promiscuously on both, and relaying traffic from one to the other when the destination network is on the far side.

Stations address their frames using a two-part identifier: `(network, station)`. The network number identifies which Econet segment; the station number identifies a specific host on that segment. A station sending to `(net=6, stn=22)` doesn't need to know which bridge(s) lie between it and network 6 — it just transmits the frame, and if it's not for a station on the local segment, any bridge that has a route will pick it up and forward.

The bridging is transparent. Senders and receivers never see the bridge as an entity; it's effectively part of the wiring.


## Hardware

The bridge box contains:

- A 6502 CPU clocked at 2 MHz
- 8 KiB of RAM (either one 6264 or four 6116s, selected by board jumpers) from `&0000`
- 8 KiB of ROM at `&E000-&FFFF` containing the firmware
- Two MC68B54 ADLCs — the Motorola HDLC/ADCCP framing chip — one per Econet port, memory-mapped at `&C800-&C803` and `&D800-&D803`
- Two 74LS244 octal buffers that read the per-port network-number jumpers into memory addresses `&C000` and `&D000`
- A single LED, driven by the `LOC/DTR` output pin of the side-B ADLC
- A momentary push-button connected to the 6502's `~IRQ` line, for entering self-test

Notably absent:

- No station-number jumpers. The Bridge has no station address on either network — see [*The Econet Bridge has no station address*](bridge-has-no-station-number.md) for why this isn't a gap.
- No ADLC `~IRQ` line to the 6502. The firmware polls SR1 bit 7 (the chip's IRQ summary) instead. The `~IRQ` pin is dedicated to the push-button.
- No external storage, no configuration interface, no serial port.

[Ian Stocks's reverse-engineered schematic](https://stardot.org.uk/forums/download/file.php?id=26508) [requires Stardot login] shows the board layout.


## Boot

The [reset handler](address:E000@variant_1?hex) runs the following sequence end-to-end:

1. **Initialise the routing tables.** [`init_reachable_nets`](address:E424@variant_1?hex) clears two 256-byte tables at `&025A` (`reachable_via_b`) and `&035A` (`reachable_via_a`), then marks the Bridge's own two network numbers and the broadcast slot (`255`) as known. See below for what these tables mean.

2. **Initialise both ADLCs.** [`adlc_a_full_reset`](address:E3F0@variant_1?hex) and [`adlc_b_full_reset`](address:E40A@variant_1?hex) each send the standard sequence `CR1=&C1`, `CR4=&1E`, `CR3=&00`, `CR1=&82`, `CR2=&67` to their ADLC — reset both sections, configure 8-bit NRZ, then enter idle listen mode.

3. **Size the RAM.** [`ram_test`](address:E00B@variant_1?hex) scans pages from `&1800` upward, writing `&AA` and `&55` patterns to each and reading them back; the last page that verifies is recorded at `&82` as `top_ram_page`. The test uses an `INC $00` between each write and read as a defence against data-bus residue and address-line aliasing — see [*Anti-aliasing in the Econet Bridge's RAM test*](ram-test-anti-aliasing.md).

4. **Announce presence on both sides.** [`build_announce_b`](address:E458@variant_1?hex) constructs a bridge-announcement frame addressed as a full broadcast (`dst_stn = dst_net = &FF`) with control byte `&80`, port `&9C`, and a single payload byte giving the Bridge's *other-side* network number. The same frame is then transmitted first on side A (payload = `net_num_b`) and then on side B (after patching the payload to `net_num_a`). See [*One frame, two broadcasts*](two-broadcasts-one-template.md).

5. **Fall through to the main loop.** No "boot complete" flag, no observable boundary between reset and steady state; execution just continues into the main loop.

If any of the final `wait_adlc_*_idle` or `transmit_frame_*` calls takes its timeout path, the reset handler is bypassed entirely and execution goes straight into the main loop anyway — see [*Escape-to-main control flow*](escape-to-main-control-flow.md) for the mechanism.


## Steady state: the main loop

The [main loop](address:E051@variant_1?hex) is small. Its header re-arms both ADLCs (clearing any lingering status from a previous frame), then enters a tight polling loop at [`main_loop_poll`](address:E079@variant_1?hex) that tests SR1 bit 7 — the IRQ summary — on each chip in turn:

- If ADLC B has raised IRQ, jump to [`rx_frame_b`](address:E263@variant_1?hex).
- Otherwise, if ADLC A has raised IRQ, jump to [`rx_frame_a`](address:E0E2@variant_1?hex).
- Otherwise, enter the idle path at [`main_loop_idle`](address:E089@variant_1?hex).

The idle path decrements a 16-bit timer (`announce_tmr_lo/hi`). When the timer reaches zero, it invokes the re-announcement code, which rebuilds and retransmits the bridge-announcement frame — on side A if `announce_flag`'s bit 7 is clear, on side B otherwise — and decrements a counter. Once the counter runs out, `announce_flag` is cleared and the idle path goes quiet until something else re-enables it.

The pattern is deliberately simple. There are no buffers queued between decisions, no stateful transactions in progress between polling iterations, no threads. Every iteration starts from a clean ADLC state and either processes one inbound frame, or processes one re-announce tick, or does nothing. Failures don't need per-iteration recovery logic because every iteration is functionally idempotent.


## Inbound frame processing

When an ADLC IRQ fires, one of the two `rx_frame_?` handlers runs. Each has the same three-stage structure:

1. **Addressing filter.** The first two bytes of the incoming frame (`rx_dst_stn`, `rx_dst_net`) are drained from the RX FIFO. If the destination network is zero (meaning "my local network" from the sender's perspective) or not in the `reachable_via_?` table, the frame is dropped and the Bridge returns to listening.

2. **Drain.** The rest of the frame is read into a 20-byte buffer at `&023C` onward. After the drain, an end-of-frame check verifies the ADLC's Frame Valid bit; if the frame is corrupt or truncated, the Bridge aborts.

3. **Dispatch.** If the destination is `(&FF, &FF)` — a full broadcast — *and* the port is `&9C` (the bridge-protocol port), the control byte is used to dispatch to a bridge-protocol handler (`&80`, `&81`, `&82`, `&83`). Anything else falls to the forwarding path.

The forwarding path — [`rx_a_forward`](address:E208@variant_1?hex) / [`rx_b_forward`](address:E389@variant_1?hex) — is where the real work happens, and where the architecture gets genuinely clever: see [*Bridging the four-way handshake*](four-way-handshake-bridging.md) for how the Bridge implements Econet's scout/ACK/data/ACK transaction across two segments.


## The bridge protocol

Four control-byte values on port `&9C` define the bridge protocol:

- **`&80` — initial announcement.** A bridge that has just come up broadcasts this to advertise itself. Recipients forget all learned routing (a new bridge may change the topology), schedule their own burst of re-announcements at staggered timing (seeded from their own network number, to avoid on-wire collisions), and fall through to the `&81` processing.

- **`&81` — re-announcement.** Payload is a variable-length list of network numbers the sender can reach. Each recipient records these in its routing table as "reachable via this side", appends its own network number to the payload, and re-broadcasts the augmented frame on the other side. The result is a distance-vector flood: every bridge in the mesh eventually hears about every network, and about every bridge in between.

- **`&82` — general query ("any bridges?").** A station or bridge uses this to ask "who's out there?". Every bridge that hears the query responds with a two-frame exchange (scout then data) telling the querier which network the bridge serves on each side. The response transmissions are delay-staggered by the bridge's own network number via [`stagger_delay`](address:E448@variant_1?hex), so multiple bridges don't respond at the same millisecond.

- **`&83` — targeted query ("can you reach network X?").** Like `&82` but with a specific network number (`rx_query_net`, at offset 13 of the query payload); only bridges that have that network in their `reachable_via_?` table bother to respond.

The query responses cleverly reuse the control-byte and port-number fields of the response *data* frame to carry the two bytes of information they need to send back: the Bridge's two network numbers. No data payload is needed — the answer fits in the frame header.


## Failure and self-test

The firmware doesn't have anything that looks like an error-handling framework. There are no exception vectors, no panic routines, no "log and continue" helpers. Every routine that might fail takes the `PLA / PLA / JMP main_loop` exit (see [*Escape-to-main control flow*](escape-to-main-control-flow.md)). This is the only recovery mechanism, and it works by jumping back to a place where the invariants are known to hold.

The self-test is entered via the IRQ/BRK vector when the push-button is pressed. It runs an indefinite loop of eight sub-tests:

1. Zero-page integrity check
2. ROM checksum (expected sum mod 256 = `&55`)
3. `&55`/`&AA` pattern test across 8 KiB of RAM
4. Incrementing-byte pattern test (catches address-line faults)
5. ADLC register-state checks on both chips
6. Loopback test A → B (requires a cable between the two ports)
7. Loopback test B → A
8. Network-number jumper check (expects `net_num_a=1`, `net_num_b=2`)

The LED serves four distinct functional states — lit solid during a healthy self-test, dark in normal operation, and two different blink patterns for the two classes of failure (countable for specific failures, uncountable for RAM failures). See [*The self-test LED*](led-self-test-indicator.md) for the full failure-mode analysis.


## Reading list

The writeups in `docs/analysis/` cover specific aspects in depth:

- [*Anti-aliasing in the Econet Bridge's RAM test*](ram-test-anti-aliasing.md) — the `INC $00` trick and why naive memory tests are unreliable.
- [*Escape-to-main: the Bridge's cooperative error-recovery idiom*](escape-to-main-control-flow.md) — the `PLA/PLA/JMP main_loop` pattern that replaces an error-handling framework.
- [*One frame, two broadcasts*](two-broadcasts-one-template.md) — how the reset-time announcement re-uses a single buffer.
- [*The Econet Bridge has no station address*](bridge-has-no-station-number.md) — why the Bridge sits on each segment without claiming a station number, and what the `&18` firmware marker in outbound frames is for.
- [*Bridging the four-way handshake*](four-way-handshake-bridging.md) — how `rx_a_forward` implements full Econet scout/ACK/data/ACK forwarding through a sequence of receive-and-stage + transmit pairs.
- [*Frame-buffer capacity and the dynamic RAM ceiling*](frame-buffer-capacity-and-ram-sizing.md) — how much frame a standard 8 KiB bridge can absorb, and what the firmware would do if more RAM were fitted.
- [*The self-test LED*](led-self-test-indicator.md) — how one ADLC output pin encodes four distinct functional states.


## External references

- [Econet Installation Guide, chapter 3](../Econet%20Installation%20Guide%200482,009%20Issue%201%2027%20September%201988.pdf) — Acorn's own description of how the Bridge is deployed.
- [MC68B54 datasheet](https://github.com/acornaeology/acorn-econet-bridge/raw/master/docs/Motorola-MC68B54P-datasheet.pdf) — authoritative reference for the ADLC's register semantics.
- [Ian Stocks's reverse-engineered schematic](https://stardot.org.uk/forums/download/file.php?id=26508) [requires Stardot login] — the board layout from which the hardware map is derived.
- [J.G. Harston's BRIDGE.SRC](https://mdfs.net/System/ROMs/Econet/Bridge/BRIDGE.SRC) — another analyst's disassembly of the same binary, written as BBC-BASIC embedded-assembler source. Assembles to the same addresses we annotate, so serves as a useful second reading. JGH is a fellow reverse-engineer, and his comments have been weighed against the evidence, like ours.
