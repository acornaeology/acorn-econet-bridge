# Anti-aliasing in the Econet Bridge's RAM test

A close reading of a thirteen-instruction loop in the Acorn Econet Bridge ROM that probes for usable RAM. It's nominally a textbook two-pattern memory test, but a single `INC` instruction makes it considerably more robust than it first appears — guarding simultaneously against two kinds of false-positive that would happily mislead a more naive implementation.


## The code

The Bridge boots with its RAM size unknown — the Econet Bridge board can be populated either with one 8 KiB 6264 chip, or with four 2 KiB 6116 chips (selected by soldered links), and the firmware is expected to discover how much RAM it has at power-on. The [reset handler](address:E000@variant_1?hex) dispatches to this short routine [`ram_test`](address:E00B@variant_1?hex):

```
                ldy #0
                sty mem_ptr_lo          ; &80 = 0
                lda #&17
                sta mem_ptr_hi          ; &81 = &17

.ram_test_loop
                inc mem_ptr_hi          ; &81 → &18 on first iteration
                lda #&AA
                sta (mem_ptr_lo),y      ; write &AA to start of page
                inc $00                 ; anti-aliasing tripwire
                lda (mem_ptr_lo),y      ; read back
                cmp #&AA
                bne ram_test_done       ; mismatch → end of RAM

                lda #&55
                sta (mem_ptr_lo),y      ; write &55 to same location
                inc $00                 ; anti-aliasing tripwire
                lda (mem_ptr_lo),y      ; read back
                cmp #&55
                beq ram_test_loop       ; both patterns OK → next page

.ram_test_done
                dec mem_ptr_hi          ; back off one page
                lda mem_ptr_hi
                sta top_ram_page        ; &82 = highest usable page
```

Two alternating patterns (`&AA` = `1010_1010`, `&55` = `0101_0101`) are written to the first byte of each candidate page and read back. The highest page that verifies is recorded at `&82` as `top_ram_page`, used downstream by workspace initialisation.

The curiosity is the pair of `INC $00` instructions, apparently to no purpose. `$00` is never read elsewhere; it has no visible meaning. What is it doing?


## The problem: naive RAM probing is unreliable

The temptation with a ROM-based RAM test is to assume that if you write a byte and read back the same byte, RAM must be there. On real hardware this is not safe.

### Data-bus residue

When the 6502 writes to an unmapped address, no chip responds — but the CPU has still driven the data bus with the value being written. The data bus on a BBC-generation 6502 board has enough capacitance to hold that value for some microseconds after the drivers release it. If the next instruction reads the same address and no chip drives the bus, the CPU samples whatever the bus happens to still be carrying. Very often, that's exactly the value just written.

A naive `STA / LDA / CMP` loop therefore false-reports RAM everywhere it probes, because it is reading back its own ghost.

### Address-line aliasing

The Bridge's address decoder is implemented in small-scale TTL. If a decoder input is miswired (or if the two variants of the RAM population option have subtly different decode rules), a write to `&1800` might physically land at some _other_ address — for instance, aliasing back into zero page, or folding high-address pages onto low ones.

Under aliasing, the write-read pair succeeds because both halves target the same physical location, even though the location isn't the one the code is probing. Naive test again: false positive.

Both failure modes are genuine risks on a mid-1980s microcomputer. The Bridge's self-test (entered from the IRQ push-button) carries an explicit ROM checksum specifically because TTL-era hardware was known to misbehave in ways that a simple CMP can't distinguish from success.


## The defence: three mechanisms, layered

The `INC $00` between write and read breaks both failure modes, in slightly different ways. Combined with the two-pattern test, three independent mechanisms have to fail simultaneously for a false positive to slip through.

### Mechanism 1: bus disturbance

`INC $00` is a zero-page read-modify-write. On the NMOS 6502 it takes five cycles, three of which are memory accesses:

```
  cycle 3:  READ    from $00   — bus driven with $00's current value
  cycle 4:  WRITE   old value  — 6502 "dummy write" quirk
  cycle 5:  WRITE   new value  — bus driven with incremented value
```

Each of those accesses actively drives the data bus with values unrelated to the memory-test pattern. Whatever residue of `&AA` was lingering after the `STA` has been comprehensively clobbered by the time the `LDA` happens. If the target page has no RAM, the `LDA` now samples whatever `INC` last drove — typically _not_ `&AA`. The `CMP #&AA` correctly reports mismatch.

### Mechanism 2: zero-page tripwire

If the broken decoder aliases the target address into zero page, the `STA (ptr),Y` to (say) `&1800` physically writes to some address in the `&00-&FF` range. For the test to false-pass, the read from `&1800` must return that same value. But between the write and the read, `INC $00` has changed location `$00`. If the alias target happens to be `$00`, the value at the alias is now `&AB`, not `&AA`. CMP fails, and the aliasing is correctly detected.

`$00` is chosen specifically because it's the most plausible alias landing point for a decoder that's lost its high-order address bits. Any zero-page location would work, but `$00` is the one most likely to be hit by a broken decoder collapsing towards low addresses.

### Mechanism 3: complementary patterns

Testing with `&AA` and then `&55` is a classic memory-test technique: the two values are bitwise complements, so for the test to pass the storage cell must be able to hold both a 1 and a 0 in every bit position. A stuck bit is detected on whichever pattern it contradicts.

Critically for this analysis, a single-value bus-residue effect can't fool both patterns simultaneously. If the bus happens to hold `&AA` residue long enough to spoof the first check, it still has to hold `&55` residue for the second — which would require the residue to be the _negation_ of the value just written. No passive-capacitance mechanism does that.


## Why it matters

Three mechanisms addressing three distinct failure modes:

| Failure mode                       | Defeated by                                  |
|------------------------------------|----------------------------------------------|
| Data-bus residue (no RAM)          | `INC $00` drives the bus with a different value between write and read |
| Alias-to-zero-page (broken decoder)| `INC $00` disturbs `$00` specifically, catching the alias landing point |
| Stuck bit (bad cell)               | Two-pattern test with `&AA` / `&55` complements |

The routine reassembles to thirteen instructions and runs in a fraction of a millisecond, yet defeats three categories of silent failure that would otherwise let the Bridge boot with a dishonest idea of how much RAM it has. It's the sort of code that looks trivial until you ask why an instruction that does nothing is there — and then reveals an author with a precise model of what the 6502 bus does and does not guarantee.


## Cross-references

- `top_ram_page` (`&82`) is consumed downstream by workspace initialisation — the reset handler [at `&E02D`](address:E02D@variant_1) onward carries the value forward.
- The Bridge's board layout — including the RAM-population option links that make this dynamic sizing necessary — is documented in [Ian Stocks's reverse-engineered schematic](https://stardot.org.uk/forums/download/file.php?id=26508).
