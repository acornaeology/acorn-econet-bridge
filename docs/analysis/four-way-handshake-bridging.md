# Bridging the four-way handshake: how forwarding really works

The Acorn Econet Bridge's forward path is substantially more subtle than it looks at first read. A casual glance at `rx_a_forward` suggests a simple "receive from A, retransmit on B" relay — but the routine runs through seven distinct stages of ADLC traffic, and three of them transmit a buffer whose contents are never built by the obvious code path. Working out what those extra transmissions were doing was the key that turned a puzzling sequence of instructions into a clean implementation of Econet's end-to-end frame-exchange protocol.

This note reconstructs the reasoning: what the Econet four-way handshake is, what a bridge between two segments has to do about it, and how the ROM implements that as a tight sequence of calls to three small helper routines.


## Background: the Econet four-way handshake

An Econet data frame is not a single packet. Because the physical layer is a cheap, low-bit-rate shared bus with no full carrier detect and no collision-repair, Acorn chose a transaction design that is firmly conservative: every data transmission is a four-way exchange, with explicit acknowledgement at both ends.

A transmission consists of:

1. **Scout** (A → B). Sender `A` broadcasts a scout frame — destination station and network, source station and network, control byte, port — onto its segment. The recipient `B` sees its own address and asserts the ADLC's address-present interrupt.

2. **Scout ACK** (B → A). `B` replies with a short frame echoing the addresses and control byte, confirming that it is ready to receive data.

3. **Data** (A → B). `A` sends the payload — the actual content of the conversation, framed as another HDLC frame with the same addresses and control.

4. **Data ACK** (B → A). `B` confirms receipt of the data, closing the transaction.

At the ADLC level, each of these four frames is a complete scout or data frame — a start-of-frame flag, addresses, optional payload, CRC, end-of-frame flag. Only after all four have been exchanged is the transmission complete.

Crucially for our purposes, the four frames have to happen in sequence, with relatively tight timing, on the same physical Econet segment. If any frame is missed or corrupted, the transaction aborts and the sender has to start again.


## The problem for a bridge

A bridge sits between two segments, let's call them `A` and `B`. Consider a station on segment A addressing a frame to a station on segment B:

- The scout goes out onto A and reaches the bridge, not the intended recipient.
- For the transmission to succeed, the scout must also reach the recipient on B — the bridge has to _forward_ it.
- But the recipient's scout ACK is going to appear on segment B, and needs to get back to the originator on segment A — the bridge has to forward _that_ too, in the opposite direction.
- Same for the data frame (A→B) and the final data ACK (B→A).

So: two frames per direction, in the order **scout, ACK, data, ACK**, alternating sides. The bridge has to participate as receiver on each of the four frames and as transmitter on each of the four forwards. If any of the eight operations fails, the whole transaction is off — but the failure mode should be clean: neither endpoint should be left waiting indefinitely for a frame that isn't coming.

This is what `rx_a_forward` implements.


## The implementation

The routine [`rx_a_forward`](address:E208@variant_1?hex) is the forwarding path when a scout arrives on side A that turns out to be not-for-us-but-forwardable (addressed to a station on a remote network that `reachable_via_b` says we can reach). Its structure is:

### Stage 1: forward the scout

The received scout is already in the receive buffer at `rx_dst_stn` (`&023C`) — the `rx_frame_a` routine drained it there before dispatching. `rx_a_forward` pushes those bytes directly into ADLC B's TX FIFO, two at a time, with an `wait_adlc_b_irq` poll between pairs to check `TDRA`:

```
    jsr wait_adlc_b_idle        ; CSMA on side B
    ldy #0
.rx_a_forward_pair_loop
    jsr wait_adlc_b_irq
    bit adlc_b_cr1
    bvc rx_a_forward_done       ; TDRA clear -> bail
    lda rx_dst_stn,y
    sta adlc_b_tx
    ...
```

Odd-length frames send the trailing byte after the pair loop ends; `CR2=&3F` terminates the burst with end-of-frame flags.

The scout is now on segment B; the addressed station has seen it and is preparing its ACK.

### Stages 2–4: the three R/T pairs

Now the handshake proper begins. Each stage is a receive-and-stage on one side followed by a transmit on the other:

```
    lda #&5A                    ; reset mem_ptr to &045A
    sta mem_ptr_lo              ; (the staging buffer for the next
    lda #4                      ;  receive-for-forward)
    sta mem_ptr_hi

    jsr handshake_rx_b          ; Stage 2: receive ACK1 on B
    jsr transmit_frame_a        ;          forward ACK1 to A

    jsr handshake_rx_a          ; Stage 3: receive DATA on A
    jsr transmit_frame_b        ;          forward DATA to B

    jsr handshake_rx_b          ; Stage 4: receive ACK2 on B
    jsr transmit_frame_a        ;          forward ACK2 to A

    jmp main_loop               ; done
```

Each `handshake_rx_?` call does two related things in one subroutine:

- **Drain**: read the frame from its ADLC into the staging buffer at `&045A` onward, pair-at-a-time, byte-by-byte, stopping either at end-of-frame or at the RAM limit set by the boot-time `top_ram_page`.
- **Stage**: set `tx_end_lo` and `tx_end_hi` so the drained length is known, normalise the staged frame's `src_net` and `dst_net` fields against the Bridge's own network numbers, and reset `mem_ptr_hi` so the next `transmit_frame_?` reads the staged frame from the right place.

Because the staging setup is done inside `handshake_rx_?`, the calling code's `transmit_frame_?` immediately afterwards has everything it needs to transmit the just-received frame verbatim on the other port. No extra bookkeeping at the call site.

### Mirror symmetry

[`rx_b_forward`](address:E389@variant_1?hex) is the exact mirror, with every occurrence of "A" and "B" swapped. Scout goes inline to ADLC A; the three handshake rounds are `handshake_rx_a` + `transmit_frame_b`, `handshake_rx_b` + `transmit_frame_a`, `handshake_rx_a` + `transmit_frame_b`. The B-A-B transmit pattern at the tail is the same handshake viewed from the other direction.


## Why it aborts cleanly

The failure mode of the whole scheme is one of its nicer features. Each `handshake_rx_?` call is an **escape-to-main** routine (see [the escape-to-main writeup](escape-to-main-control-flow.md)): if it times out waiting for the expected frame, or if the Frame-Valid check fails, or if the `dst_net` isn't reachable on the far side, it takes the `PLA / PLA / JMP main_loop` exit, abandoning the in-flight transaction and jumping straight back to the dispatcher.

The consequences of that abort are exactly what we want:

- **No half-forwarded state.** The bridge was going to relay four frames; if a middle frame doesn't arrive, the remaining frames don't get forwarded either. Neither segment sees a stray, incomplete exchange that might confuse its participants.

- **The endpoints notice.** Because Econet's handshake timing is tight (microseconds to milliseconds between stages), if the bridge drops out mid-transaction the sender's own ADLC will time out waiting for its next expected frame and raise its own error. The sender is then free to retry; the recipient, by the same token, times out and releases its receive state. Neither is stuck.

- **The bridge just keeps going.** By the time `main_loop` starts its next cycle, both ADLCs are re-armed (by the main-loop header), both `reachable_via_?` tables are intact (nothing modified them during the failed handshake), and the next frame on either side is treated independently. No per-transaction state exists to get out of sync.

This is what makes the pattern work at all. A bridging protocol that tried to carry explicit transaction state would need recovery logic — timeouts, sequence numbers, retries. The Bridge has none of that. It relies on the fact that every transaction has exactly two ends, both of which have their own independent timeout handling, and all it has to do is stop participating whenever something goes wrong.


## Why we couldn't see it at first

For a long time during the disassembly, `sub_ce56e` and `sub_ce5ff` were labelled as "listen restore" helpers. That mis-interpretation was natural enough — they always appear immediately after a `transmit_frame_?` call, and their `CR1 = &82` / `CR2 = &67` prologue looks exactly like the listen-mode configuration at the tail of `adlc_*_full_reset`. It was the _drain_ body inside them that gave them away: unconditional reads from `adlc_?_tx` into `(mem_ptr_lo),Y`, `top_ram_page`-bounded, with a CR2-based end-of-frame test. That's a receiver, not a restore.

Once that recognition clicked, the three trailing `transmit_frame_?` calls in `rx_a_forward` resolved instantly. They aren't redundant; they aren't announcement bursts; they aren't mysterious. They are the three forward-after-receive pairs of the four-way handshake, with the scout having been handled by the inline loop that precedes them.

The misdirection came partly from the naming. A `listen_restore_a` routine would fit the call pattern perfectly if you only looked at where it's called. Only by reading the body does its real job become visible. It's a small reminder that call-graph structure is a hypothesis about semantics, not evidence — and that in a ROM this compact, every subroutine is likely pulling double duty.


## Cross-references

- [`rx_a_forward`](address:E208@variant_1?hex) and its mirror [`rx_b_forward`](address:E389@variant_1?hex).
- [`handshake_rx_a`](address:E56E@variant_1?hex) and [`handshake_rx_b`](address:E5FF@variant_1?hex) — the receive-and-stage routines.
- [`transmit_frame_a`](address:E517@variant_1) / [`transmit_frame_b`](address:E4C0@variant_1) — the transmit halves they pair with.
- [Escape-to-main control flow](escape-to-main-control-flow.md) — the error-recovery mechanism that makes mid-handshake failures safe.
- [The Bridge has no station address](bridge-has-no-station-number.md) — explains why the forwarded frames' `src_stn`/`dst_stn` are treated as opaque bytes by the bridge.
