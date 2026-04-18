# One frame, two broadcasts: the Bridge's reset-time announcement

At power-on the Econet Bridge tells each of its two connected networks that it exists. Stations on side A need to know that any packet addressed to a network beyond A can be forwarded via the bridge's station number on A; stations on side B need the corresponding information about their own side. The Bridge therefore has to send two logically different announcement frames, one out through each ADLC.

The obvious implementation would build two frames, once each, and send each one through the appropriate ADLC. The Bridge does something smaller: it builds a single frame, transmits it via one ADLC, patches one byte, and transmits it again via the other ADLC. One frame template, two broadcasts, one byte of difference between them.

This note documents the idiom.


## The frame

The outbound frame-control block sits in RAM at `tx_dst_stn..tx_data0` (`&045A-&0460`). It has the standard Acorn Econet scout-frame shape:

```
  &045A  tx_dst_stn      destination station
  &045B  tx_dst_net      destination network
  &045C  tx_src_stn      source station
  &045D  tx_src_net      source network
  &045E  tx_ctrl         control byte
  &045F  tx_port         port number
  &0460  tx_data0        trailing payload byte (optional)
```

A frame builder populates these bytes, sets a 16-bit end-pointer pair (`tx_end_lo`/`tx_end_hi` at `&0200`/`&0201`) to tell the transmit routine how far to scan, and optionally sets X to indicate whether the trailing `tx_data0` byte should be sent after the main bytes. The builders for the reset-time announcement write `tx_end_lo = &06`, `tx_end_hi = &04` — end address `&0406` combined with a buffer start of `&045A` means the transmit sends bytes `0..5` of the buffer, then optionally one more byte at offset `6`.

All of this is called through [`transmit_frame_a`](address:E517@1?hex) or its byte-for-byte mirror [`transmit_frame_b`](address:E4C0@1?hex), which read from the same buffer via the zero-page pointer `mem_ptr_lo`/`mem_ptr_hi`. The transmit routines don't care which buffer they're reading from or what it contains; they just push bytes into their ADLC's TX FIFO until the end-pointer is reached.


## The reset sequence

The relevant part of the reset handler is short enough to inline:

```
    jsr build_announce_b           ; populate &045A-&0460 with a
                                   ; bridge-announcement template
                                   ; (dst = FF FF, ctrl = &80,
                                   ; port = &9C, data0 = station_id_b,
                                   ; X = 1 so data0 is sent)

    jsr wait_adlc_a_idle      ; wait for ADLC A to be ready
    jsr transmit_frame_a           ; ...and send the frame via side A

    lda station_id_a               ; patch: overwrite the trailing byte
    sta tx_data0                   ; with station_id_a

    lda #4                         ; reset mem_ptr_hi (transmit_frame_a
    sta mem_ptr_hi                 ; leaves it pointing at &045A, but
                                   ; belt-and-braces)

    jsr wait_adlc_b_idle      ; wait for ADLC B to be ready
    jsr transmit_frame_b           ; ...and send the same frame via side B

    ; fall through to main_loop
```

Twelve instructions after the frame is built, and the Bridge has announced itself on both networks.


## Why this works

The trick hinges on what the two broadcasts actually need to say.

Every other field in the frame is identical between the two transmissions:

- **Destination station / network** are both `&FF`, the broadcast address — the same in either direction.
- **Source station / network** are fixed firmware constants — the same either way.
- **Control byte** is `&80` — the same scout-control value for both announcements.
- **Port** is `&9C`, the Bridge-protocol port — the same.

The _only_ byte that differs between what side A needs to be told and what side B needs to be told is the station-ID payload. Side A needs to learn the bridge's ID on side B; side B needs to learn the bridge's ID on side A. That's one byte, at one known offset.

Patching a single byte between two calls to the transmit routine is therefore all the work required. The rest of the buffer is reusable verbatim.


## The subtlety

The asymmetry between `build_announce_b` and the reset sequence is what makes the idiom work: the builder's name suggests it builds a "side-B announcement", but what it actually does is populate the template with `tx_data0 = station_id_b`. That's the *first* of the two transmissions — the one sent via ADLC A, announcing to side A what the Bridge's station number is on the opposite (B) side.

After that first transmission, the reset handler rewrites `tx_data0` with `station_id_a` so that the second transmission — sent via ADLC B — announces the Bridge's side-A station number to the stations on side B. No second builder routine; no second frame; no second buffer. Just a one-byte patch and a call through the mirror of the transmit routine.

There's a corresponding non-trivial naming decision in the disassembly: I've labelled the builder `build_announce_b` because it sets the payload to `station_id_b`, but the frame it produces is transmitted to side A. The name describes the contents, not the destination. Rename candidates (`build_announce_payload_b`? `build_for_far_side_b`?) all end up more awkward. I've left it as `build_announce_b` and noted the subtlety in the driver.


## What the idiom tells us

This is not a clever optimisation hiding behind a complex abstraction. It's a direct consequence of noticing that two logically distinct operations have almost all their work in common, and committing to doing the common part once. Building the frame is fiddly enough that duplicating it would be visible in the disassembly: setting seven header bytes and an end-pointer pair runs to around forty bytes of code per builder. By contrast, the patch is three instructions.

It also tells us that the author was comfortable reasoning about the transmit routine's behaviour in terms of what's in the buffer rather than what the builder looks like. The transmit path is _stateless_ in the high-level sense: it just sends the bytes it's pointed at. Any caller can set up any buffer contents, call `transmit_frame_{a,b}`, and the frame goes out. That separation of concerns — builder owns content, transmitter owns wire format — is what makes the patch-and-resend idiom possible at all.

The same discipline opens the door to reusing the transmit routines for frames with more structure later: frames with multiple payload bytes, different headers, different destinations. The reset-time dual-announce is the simplest instance of a pattern the ROM uses elsewhere, where one buffer and one transmit routine serve several distinct outbound operations.


## Cross-references

- [`build_announce_b`](address:E458@1?hex) — the template builder.
- [`transmit_frame_a`](address:E517@1?hex) and [`transmit_frame_b`](address:E4C0@1?hex) — the mirrored transmit routines.
- The outbound frame control block at `tx_dst_stn..tx_data0` (`&045A-&0460`).
- The reset sequence calling the pair at [`&E038`](address:E038@1) onward.
