# Frame-buffer capacity and the dynamic RAM ceiling

How big a frame can the Econet Bridge absorb? The answer is governed by one byte of zero-page workspace – `top_ram_page` at `&82` – and two `CMP` instructions. Together they decide where the staging buffer ends and, by extension, how much of an inbound frame will fit before the bridge gives up mid-handshake. This writeup works the arithmetic out for the standard 8 KiB configuration, then asks what the firmware would do if more RAM were fitted.


## The staging buffer and its single bound

Both sides of the four-way handshake drain received frames into a single staging area starting at `&045A`. The caller sets `mem_ptr_lo = &5A` and `mem_ptr_hi = &04`, then [`handshake_rx_a`](address:E56E@variant_1?hex) or [`handshake_rx_b`](address:E5FF@variant_1?hex) reads bytes from the ADLC and stores them via `(mem_ptr_lo),Y` until either the frame ends or the buffer fills. See [*Bridging the four-way handshake*](four-way-handshake-bridging.md) for why these routines exist and how the handshake uses them.

The "buffer fills" case is the bound we care about. Its core is three instructions repeated at `&E5AD` (A) and `&E63E` (B):

```
    inc mem_ptr_hi
    lda mem_ptr_hi
    cmp top_ram_page
    bcc handshake_rx_?_pair_loop    ; still room – keep draining
    ; fall through to handshake_rx_?_escape
```

The bounds test happens once per 256 bytes of payload, after Y has wrapped and the page counter has been stepped. When the just-incremented `mem_ptr_hi` reaches `top_ram_page`, the `BCC` fails and the routine falls into its escape – `PLA / PLA / JMP main_loop` – abandoning the whole handshake. See [*Escape-to-main control flow*](escape-to-main-control-flow.md) for why that's safe.

Two consequences are worth noting up front:

1. **The comparison is strictly less than.** When `mem_ptr_hi` reaches `top_ram_page` the escape fires, so the highest page actually used as a buffer is `top_ram_page - 1`. The verified page at `top_ram_page` itself is always left idle – 256 bytes of perfectly-good RAM sacrificed to keep the comparison to two instructions.

2. **`top_ram_page` is one byte.** The bound is page-granular, and it can never exceed `&FF`. The drain therefore cannot span more than 64 KiB of address space regardless of how much RAM is physically present.


## The arithmetic for a standard 8 KiB bridge

The standard bridge has 8 KiB of RAM from `&0000-&1FFF`. [`ram_test`](address:E00B@variant_1?hex) probes pages from `&18` upward (see [*Anti-aliasing in the Econet Bridge's RAM test*](ram-test-anti-aliasing.md) for why it starts there and why the test is trustworthy), verifies `&18` through `&1F`, fails on page `&20` where no RAM answers, and backs off one page to record `top_ram_page = &1F`.

Plugging `top_ram_page = &1F` into the drain geometry: `mem_ptr_hi` starts at `4` and survives while it stays below `&1F`. That's 27 iterations, each covering 256 bytes of the 16-bit address space. The effective region written runs from `&045A` (`dst_stn` goes there by direct store) through `&1F59`. A Python simulation of the loop – stepping Y and `mem_ptr_hi` exactly as the 6502 would – confirms the total:

```
top_ram_page       = 0x1F
direct stores      = 2 bytes at 0x045A, 0x045B
loop stores        = 6910 bytes
total frame bytes  = 6912
first written addr = 0x045A
last  written addr = 0x1F59
span               = 6912 bytes (0x1B00)
page iterations    = 27
gaps in coverage   = 0
```

**6912 bytes** is the hard ceiling for a single received frame. That's comfortably an order of magnitude above any real Econet frame – `*SAVE` / `*LOAD` chunks are a few hundred bytes, and the four-way handshake's ACK frames are 4 bytes plus header – so in practice the escape path is a defensive guard rail rather than a limit anyone bumps into. But it is the limit, and pathological traffic above it is silently dropped.


## What would happen if more RAM were fitted

The bridge board was built with two RAM-population options (one 6264 or four 6116s), both delivering 8 KiB. Suppose the hardware were modified – say, by replacing the 6264 with a 62256 and adjusting the address decoder – to populate RAM contiguously above `&1FFF`. What would the existing ROM do?

The answer is that the firmware is already prepared for it, by accident or by design. `ram_test` contains no hard-coded upper bound: it just keeps stepping `mem_ptr_hi` until a page fails the two-pattern check. Give it more RAM and it will discover more RAM. No code change, no configuration, no jumper.

The natural ceiling is the I/O map. The two `station_id_?` latches live at `&C000` and `&D000`; the two ADLCs occupy `&C800-&C803` and `&D800-&D803`. When `ram_test` probes page `&C0` it would write `&AA` to the read-only `station_id_a` latch (which ignores the write) and then read the jumper-set network number back. Unless that number happens to equal `&AA`, the pattern-1 check fails immediately; in the unlikely event it does match, the subsequent `&55` check fails instead, since the latch can hold only one value. Either way, `ram_test` terminates cleanly at the I/O boundary. The maximum extensible range is therefore `&0000-&BFFF` – 48 KiB, or `top_ram_page = &BF`.

A short sweep across plausible configurations, from the same simulation:

| RAM fitted                     | `top_ram_page` | Max frame (bytes) | Drain span      |
|--------------------------------|----------------|-------------------|-----------------|
| Standard 8 KiB (`&0000-&1FFF`) | `&1F`          |             6 912 | `&045A-&1F59`   |
|          16 KiB (`&0000-&3FFF`) | `&3F`          |            15 104 | `&045A-&3F59`   |
|          32 KiB (`&0000-&7FFF`) | `&7F`          |            31 488 | `&045A-&7F59`   |
| Max contiguous (`&0000-&BFFF`) | `&BF`          |            47 872 | `&045A-&BF59`   |

Every row is reachable by the existing ROM without modification. The `handshake_rx_?` drains scale proportionally, and the escape path moves correspondingly further out.


## What wouldn't scale

Only the receive-for-forward staging buffer benefits. Every other data structure in the ROM lives at a hard-coded address and has a hard-coded size:

- **Zero page** (`&00-&FF`): scratch and pointers, fixed.
- **Hardware stack** (`&0100-&01FF`): 256 bytes, fixed by the 6502.
- **Workspace variables** (`&0200` onward): `tx_end_lo/hi` at `&0200/01`, 24-bit counters at `&0214-&0216`, the 20-byte inbound header buffer at `&023C-&024F`, the announce bookkeeping at `&0229-&022C`. All single bytes or small fixed fields.
- **Routing tables**: `reachable_via_b` at `&025A` and `reachable_via_a` at `&035A`, each 256 bytes. These are already full-size – they index the entire Econet network-number address space (8-bit, so 256 entries is the maximum any legal topology could need). Extra RAM can't make them "bigger" in any meaningful sense.
- **TX header fields** at `&045A-&0460`, shared with the front of the staging buffer.

No routine in the ROM reads `top_ram_page` other than the two drain-bounds checks at `&E5AD` and `&E63E`. There's no dynamic allocator, no multi-frame queue, no per-station table that grows with memory. An upgraded bridge would be able to absorb one much larger frame, but it would still process that frame one-at-a-time, still keep the same routing state, still re-announce on the same schedule, and still forget everything that didn't fit in the original fixed workspace.

For most real workloads this is an upgrade without a use case. Econet frames are small; the extra headroom would sit unused. The firmware would need deeper structural changes – multi-frame buffering, queued forwarding, per-station state – before the extra RAM bought you anything beyond a very large single-frame buffer. Those changes would require a new ROM; simply fitting more RAM does not.


## The self-test doesn't scale either

There is one more thing that doesn't scale, and it is more uncomfortable than the others: the diagnostic coverage. The push-button self-test entered at [`self_test`](address:F000@variant_1?hex) runs three RAM-touching scans – the `&55`/`&AA` pattern test in [`self_test_ram_pattern`](address:F070@variant_1?hex), and the fill and verify phases of the incrementing-pattern test in [`self_test_ram_incr`](address:F0A0@variant_1?hex). Each of them loads its page counter at `st_page_count` from a hard-coded immediate:

```
    lda #&20            ; f078 / f0a4 / f0be
    sta st_page_count
```

`&20` is 32 pages – exactly 8 KiB. There is no path in the self-test that consults `top_ram_page`. The scan always starts at `&0000` and always covers 32 pages, so a bridge fitted with extra RAM above `&1FFF` would have its lower 8 KiB exercised exactly as before, and the extra RAM not exercised at all.

This produces a quietly unsatisfying split. The boot-time [`ram_test`](address:E00B@variant_1?hex) would correctly *discover* extra RAM, the [`handshake_rx_?`](address:E56E@variant_1?hex) drains would correctly *use* it, but the self-test would not *check* it. A stuck bit or a failed cell at, say, `&3500` on a 16 KiB bridge would silently corrupt forwarded frames – the drain would write to the broken cell and the transmit phase would read garbage back – without the push-button test ever flagging the problem.

The bound is tight: there is no way for the existing self-test to be persuaded to cover more, short of patching the ROM. The boot-time `ram_test` is the only routine in the firmware that follows the actual size of the populated memory.


## Cross-references

- [`ram_test`](address:E00B@variant_1?hex) – the detection routine; already unbounded in the sense that matters here.
- [`handshake_rx_a`](address:E56E@variant_1?hex) and [`handshake_rx_b`](address:E5FF@variant_1?hex) – the two drain routines that compare against `top_ram_page`.
- [*Anti-aliasing in the Econet Bridge's RAM test*](ram-test-anti-aliasing.md) – why the detection is reliable even under broken address decoding.
- [*Bridging the four-way handshake*](four-way-handshake-bridging.md) – the handshake context in which the drains run.
- [*Escape-to-main control flow*](escape-to-main-control-flow.md) – what happens when the drain hits the ceiling.
