# The Econet Bridge's self-test LED, driven by a repurposed ADLC pin

The Acorn Econet Bridge has a single front-panel LED. The schematic shows its high side wired to the `~LOC/DTR` pin of IC18 — one of the two MC68B54 ADLCs on the board. The equivalent pin on the other ADLC (IC12) is simply not connected. There is no separate driver circuit, no dedicated output port, no signal-conditioning transistor. The LED is attached to an I/O chip's control pin, and software decides whether it lights.

This note documents how the Bridge firmware uses that LED, and draws out what the design tells us about how its author thought about the hardware they had on hand.


## What the firmware does

On the MC68B54, the `~LOC/DTR` pin is driven from CR3 bit 7 in non-loop mode. The datasheet is specific about the polarity, and the relevant detail is that the pin is inverted relative to the control bit:

> When the LOC/DTR control bit is high the DTR output will be low.

So writing `1` to CR3 bit 7 pulls the pin to ground; writing `0` releases it. On the Bridge schematic, the pin is connected to the low side of the LED, with the high side tied via a resistor to Vcc. Current therefore flows through the LED (and it lights) when CR3 bit 7 is high, and the LED is dark when CR3 bit 7 is low. The control bit is "active high for LED on", despite the pin being inverted, because the circuit is wired expecting a current-sink driver.

A full-ROM search for every write to CR3 on ADLC B — the ADLC with the LED — turns up exactly two:

```
&E414  (inside adlc_b_full_reset):      CR3 = &00   bit 7 = 0  ->  pin HIGH -> LED OFF
&F01C  (inside self_test_reset_adlcs):  CR3 = &80   bit 7 = 1  ->  pin LOW  -> LED ON
```

The surrounding sequences are otherwise byte-for-byte identical: both write `CR1 = &C1` (reset with AC=1), then `CR4 = &1E`, then their respective CR3 value, then `CR1 = &82`, then `CR2 = &67`. The only behavioural difference between the "run-time" reset and the "self-test" reset is the bit that drives the LED.

In normal operation, the ADLC is initialised via `adlc_b_full_reset` and CR3 stays at zero for the life of the session. The LED therefore stays dark. When the operator presses the self-test push-button on the 6502 `~IRQ` line, the IRQ/BRK vector lands at `self_test` (`&F000`), which runs `self_test_reset_adlcs` — and the LED comes on. It stays on for the duration of the self-test, since nothing else touches CR3 until a reset runs the normal `adlc_b_full_reset` sequence again.

The LED is therefore exactly one thing: a self-test-in-progress indicator.

The symmetric `CR3 = &80` write on ADLC A at `&F015` has no visible effect — IC12's `~LOC/DTR` pin isn't wired — but the firmware writes it anyway, so the two chips are treated identically. That's cheaper than special-casing one side and, just as importantly, it keeps the initialisation sequences diff-able. A reader comparing the two reset flows can see immediately that only one value differs.


## Why this is a pleasant piece of engineering

There is no dedicated circuitry for this LED. There is no port register to configure it as an output. There is no timer or flag that polls status and drives it. The LED is wired to a pin that a data-link controller happens to have spare, and the firmware uses it as a state annunciator in the only two places it needs to.

The LED's behaviour is therefore fully defined by the state of a single bit, set exactly once at self-test entry and cleared exactly once by the next normal reset. There is no drift, no flicker, no race. Two write sites, zero maintenance.

The choice to use CR3 bit 7 specifically rather than, say, a bit in CR2 is worth noting: CR3 is only addressable when CR1's AC bit is set, which in this firmware only happens inside the reset sequences. That means CR3 cannot be touched accidentally by the rest of the code. Pinning the LED to a register that's only accessed during chip init is a natural way to make the LED's state a function of "which init path did we take", which is exactly the information the LED is supposed to display.

It's a small piece of design, but it compounds three good decisions into one visible pin:

- Reuse a pin that exists anyway rather than add hardware.
- Keep the two variants of the init sequence diff-minimal, so the behavioural difference is localised to a single bit.
- Put that bit in a register that can only be reached through the init path, so the LED state is inherently synchronised with which init ran.

There's no unnecessary LED blinking or software timing involved — the Bridge simply answers "is self-test running?" with one bit of hardware, driven by one bit of firmware, and the pin was there for the taking.


## Cross-references

- `adlc_b_full_reset` at [`&E414`](../../versions/econet-bridge-1/output/econet-bridge-1.asm) in the disassembly.
- `self_test_reset_adlcs` at [`&F005`](../../versions/econet-bridge-1/output/econet-bridge-1.asm) in the disassembly.
- MC68B54 datasheet in [`docs/Motorola-MC68B54P-datasheet.pdf`](../Motorola-MC68B54P-datasheet.pdf) — CR3 bit meanings.
- Schematic (Ian Stocks's reverse-engineering) in [`docs/econet_bridge_Ian_Stocks.pdf`](../econet_bridge_Ian_Stocks.pdf).
