# The Econet Bridge has no station address

Every station on an Acorn Econet network has an eight-bit station number in the range 1-254, set by links on the host's mainboard and used by the MOS to address and filter frames. Servers have them. Printer servers have them. Even the simplest BBC Micro plugged into a piece of Econet cable needs one, or it cannot send or receive anything useful.

The Acorn Econet Bridge does not.

The Bridge plugs into two Econet segments and forwards traffic between them, but it is not addressable at the station level on either one. It never claims an identity to the stations it sits among; it simply sits there, listening promiscuously, forwarding what it should, and broadcasting its own existence when it needs to. This note sets out what the code, the datasheet and the Installation Guide each say about that architectural choice, and why it turns out to be a sensible one.


## The hardware

The Econet Bridge board carries two 74LS244 octal buffers, one per Econet port. Each 74LS244 buffers a bank of jumpered links that pull its inputs to power rails; the 6502 reads the buffered outputs from the memory-mapped addresses `&C000` (side A) and `&D000` (side B). That is the entire on-board identity configuration.

The Installation Guide (`Econet Installation Guide 0482,009 Issue 1`, chapter 3) describes how to set those links:

> "Figure 5 shows the position of the links on the bridge PCB. The row next to the component marked RP2 controls the identity of the network segment plugged into socket A; the links next to RP1 determine the identity of the network segment plugged into socket B. [...] As the range of legal identity numbers is 1-127, the top link of each row should always be made [...]."

What gets set by those links is the **network-segment identity** — the network number of the segment attached to that port. Range 1-127, seven bits effective (the top link is always "made" for a zero in bit 7). There is no second set of links anywhere on the board for a station number, on either side. The Bridge's only per-port configuration is which network number each segment carries.

The Installation Guide describes attaching the box to a cable "exactly as though the bridge box were a normal station", but from context that is clearly an electrical and mechanical instruction — same 5-pin DIN lead, same socket or terminator box — rather than a statement about logical addressing. The guide does not mention the Bridge claiming or responding to a station address anywhere in its twenty-odd pages on bridging.


## The firmware

The firmware's internal structures reflect the same asymmetry. The two 256-byte routing tables `reachable_via_b` (`&025A`) and `reachable_via_a` (`&035A`) are indexed by **destination network number**, not destination station. The Bridge's inbound-frame filter in `rx_frame_a` reads the second byte of the incoming scout (`rx_dst_net`) and consults the routing table on that value alone:

```
ldy adlc_a_tx               ; read byte 1 = rx_dst_net
beq rx_a_not_for_us         ; net 0 (local) -> ignore
lda reachable_via_b,y       ; network known?
beq rx_a_not_for_us         ; no -> ignore
```

The destination station (`rx_dst_stn`, read into the buffer at byte 0) is never used for routing decisions in either handler. It's copied into the forwarding buffer so the far side's stations can see who the frame is for, but the Bridge itself makes no station-level dispatch.

Outbound announcement frames built by `build_announce_b` are likewise station-agnostic: destination station and destination network are both `&FF` (full broadcast), and the control byte and port (`&80/&81` on port `&9C`) are what receivers key off. A receiver doesn't need to know the Bridge's station address because, as far as the on-wire frame is concerned, the Bridge doesn't have one.


## The mysterious &18

There are two bytes in the announcement frame template that briefly suggest otherwise. `build_announce_b` populates the "source station" and "source network" fields (`tx_src_stn` at `&045C`, `tx_src_net` at `&045D`) with the constant `&18`, not with either of the Bridge's configured network numbers. Both of these are the same constant and both are baked into the ROM, not read from the jumpers.

This is not a bridge identifier. There is no station-number register to draw it from in the first place. And a careful reading of the receive path in `rx_a_handle_81` confirms that the firmware on the other side ignores these bytes entirely:

```
ldy #6              ; skip the header (bytes 0-5), start at payload
.rx_a_learn_loop
    lda rx_dst_stn,y  ; read payload byte Y
    tax
    lda #&FF
    sta reachable_via_a,x
    iny
    cpy rx_len
    bne rx_a_learn_loop
```

Offsets 2 and 3 (`rx_src_stn` and `rx_src_net`) are simply not part of the input to the routing-table update. So `&18` cannot be an address, because no receiver ever treats it as one.

The most defensible interpretation is that `&18` is a **firmware marker**: a fixed byte pattern in a well-known position that lets a receiver — or an analyser, or a human with a logic probe — cross-check "is this frame a well-formed bridge announcement?" against four independent signals:

```
dst_stn = dst_net = &FF          full broadcast
src_stn = src_net = &18          firmware marker
ctrl    = &80 or &81             initial- vs re-announcement
port    = &9C                    bridge-protocol port
```

Any one of those would probably be sufficient for dispatch; taken together they form a defensive redundancy that makes bridge-protocol frames recognisable even in the face of corruption, coincidence, or misconfiguration on another station. The choice of `&18` specifically has no documented meaning in the firmware or the Installation Guide; it might as well have been `&42`.


## Why this works

Giving the Bridge no station address is not a cost-cutting shortcut — it is a positive design choice, and it has a handful of clean consequences.

**Stations don't need to know the Bridge exists.** In Acorn's bridged-network model, a station on network A addressing a frame to `(net=6, stn=22)` means "station 22 on network 6". The transmitting station writes that address into the scout frame and sends it onto its own segment. If there is a bridge between network A and network 6, the bridge picks the frame up (by seeing `dst_net=6` in a `reachable_via_*` entry), forwards it out of the other port, and the final delivery happens on the far segment. The station never had to know the bridge's address, because it was never talking to the bridge — it was talking through the bridge to a station on another network.

**Multiple bridges on one segment are automatic.** The Installation Guide notes that "all bridges connected to a given network segment should have the network's identity set to the same number". With no per-bridge station address, there's nothing to coordinate or collide on at a bridge level. Each bridge on the segment observes the same broadcast traffic and independently decides whether to forward based on its own routing table. Announcements flood across the mesh without any bridge needing to know about any other.

**The bridge is invisible to the user.** There's no `*STATIONS` entry for it, no reply to a `*I AM` probe, no station number to collide with an existing file server when the network is extended. As far as a BBC Micro user looking at their local network is concerned, the bridge is part of the wiring.

**The protocol is simpler.** With no station address, the bridge-announcement handshake has no "who are you?" step. Bridges come up, broadcast, learn from other bridges' broadcasts, and start forwarding. Every state transition is idempotent against re-hearing the same announcement; every frame is small and self-contained; no session needs to be established or torn down.


## Implications for the disassembly

For anyone working through the Bridge ROM, the practical takeaway is: don't look for station-level decision-making. Anywhere the code reads a byte that might have been a station number, it's almost certainly a network number (or an index into a network-keyed table, or the `&FF` broadcast sentinel). The one place where a station number actually appears in code is `rx_dst_stn` (byte 0 of every inbound frame) — and even that is only preserved for forwarding, never acted on locally.

The Bridge lives one level up from the station-address plane — it cares about networks, and it treats stations as opaque bytes to be forwarded unchanged. The firmware's clean separation between the two is one of the nicer architectural features of the design.


## Cross-references

- `net_num_a`/`net_num_b` at `&C000`/`&D000` — the only per-port identity the Bridge has.
- `reachable_via_a`/`reachable_via_b` at `&035A`/`&025A` — routing tables indexed by destination network number.
- [`build_announce_b`](address:E458@variant_1?hex) — writes `&18` into the otherwise-unused source-address fields of the outbound announcement.
- [`rx_a_handle_81`](address:E1EE@variant_1?hex) — demonstrates that the receiver ignores the source-address fields.
- [Econet Installation Guide, chapter 3](../Econet%20Installation%20Guide%200482,009%20Issue%201%2027%20September%201988.pdf) — the authoritative statement on how the Bridge's hardware is configured.
- [Ian Stocks's reverse-engineered schematic](https://stardot.org.uk/forums/download/file.php?id=26508) [requires Stardot login] — board-level confirmation that only the two 74LS244 network-number buffers are installed.
