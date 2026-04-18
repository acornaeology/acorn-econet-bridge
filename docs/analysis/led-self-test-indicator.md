# The Econet Bridge's status LED, driven by a repurposed ADLC pin

The Acorn Econet Bridge has a single front-panel LED. Its anode is wired to the `~LOC/DTR` pin of IC18 – one of the two MC68B54 ADLCs on the board – with the cathode tied to ground through a current-limiting resistor. The equivalent pin on the other ADLC (IC12) is simply not connected. There is no separate driver circuit, no dedicated output port, no signal-conditioning transistor. The LED is attached to an I/O chip's control pin, and software decides whether it lights.

This note documents how the Bridge firmware uses that LED, and what the design tells us about how its author thought about the hardware they had on hand. It also corrects a subtle polarity error that the earlier draft of this writeup carried, after the wiring was confirmed against Ian Stocks's schematic and Chris Oddy's replica board, and against the empirical descriptions in the Bridge service procedure (see `docs/self-test-connections.png` for the relevant scan).


## Polarity, from the pin to the panel

On the MC68B54, the `~LOC/DTR` pin is driven from CR3 bit 7 in non-loop mode. The datasheet is specific about the polarity, and the relevant detail is that the pin is **inverted** relative to the control bit:

> When the LOC/DTR control bit is high the DTR output will be low.

So writing a `1` to CR3 bit 7 pulls the pin to ground; writing a `0` releases it (the chip drives it high). On the Bridge schematic, the pin is connected to the **anode** of the LED, with the cathode going to ground via a resistor. Current flows through the LED – and it lights – when the pin is **high**. The pin is high when CR3 bit 7 is **clear**. So the chain is:

| CR3 bit 7 | LOC/DTR control bit | `~LOC/DTR` pin | LED      |
|-----------|---------------------|----------------|----------|
| `0`       | low                 | **high**       | **lit**  |
| `1`       | high                | **low**        | **dark** |

The double inversion (datasheet's bit-to-pin inversion combined with the anode-to-pin wiring) means the natural reading – "set the bit to light the LED" – is the wrong way round. CR3 bit 7 = 0 lights the LED, and that is the value the chip leaves CR3 in after a hardware or software reset that clears its control bits.

The MC6854 datasheet adds one more wrinkle worth knowing: while the chip is in a reset state (either the hardware `RESET` pin asserted or `CR1` written with both `Tx Reset` and `Rx Reset` set), the `~LOC/DTR` output is forced high regardless of CR3, and the relevant control bits – including the LOC/DTR bit – are themselves cleared by the reset. So a full ADLC reset always lights the LED both directly (during the reset window) and indirectly (by clearing CR3 bit 7, which keeps the pin high after the reset is released).


## Steady state: lit during normal operation

In normal operation, the boot reset handler initialises ADLC B via [`adlc_b_full_reset`](address:E40A@variant_1?hex), whose CR3 write is:

```
&E414  (inside adlc_b_full_reset):  CR3 = &00   bit 7 = 0  →  pin HIGH  →  LED LIT
```

CR3 stays at zero for the entire life of the running bridge: nothing in the steady-state code path touches it. The LED therefore stays **lit** continuously while the bridge is in normal service – which is exactly the behaviour the manual reports: *"switch the unit off and on again. The LED should now remain on."*

The LED's "always-on in normal operation" role is, in practice, a power-and-bridge-firmware-OK indicator. It tells an observer at a glance that the box has power, that the boot path completed, and that the firmware reached `main_loop` cleanly enough to finish initialising both ADLCs.


## Self-test entry: the LED goes dark

Pressing the self-test push-button on the 6502 `~IRQ` line vectors execution to [`self_test`](address:F000@variant_1?hex), which runs [`self_test_reset_adlcs`](address:F005@variant_1?hex). Its CR3 write is:

```
&F01C  (inside self_test_reset_adlcs):  CR3 = &80   bit 7 = 1  →  pin LOW  →  LED DARK
```

This is the "self-test in progress" marker the firmware author planted: the moment the operator presses the button, the LED visibly extinguishes. Apart from that one bit, the surrounding init sequence at `&F005` is byte-for-byte identical to `adlc_b_full_reset`, so the only behavioural difference between the two reset paths is the LED's state coming out of init.

That much was correctly identified in the earlier draft of this writeup. What it got wrong was the polarity – it claimed CR3 = &80 *lit* the LED – and the consequence, that the LED stays solid throughout a healthy self-test. Both were the wrong way round, and the empirical evidence was the manual's procedure step: *"the LED in the recess should flash with an even mark-space ratio"*.


## Why the LED visibly flashes during a healthy self-test

The simple two-write model – "self-test sets CR3 = &80, normal reset clears it back to &00" – misses what happens to CR3 bit 7 *during* a self-test pass. The self-test runs eight sub-tests, two of which are loopback exchanges between the two ADLCs ([`self_test_loopback_a_to_b`](address:F10A@variant_1?hex) and [`self_test_loopback_b_to_a`](address:F1AB@variant_1?hex)). Each loopback test begins by issuing:

```
    lda #&c0
    sta adlc_b_cr1     ; full reset on B (TxRS + RxRS set, AC=0)
```

A full reset, per the MC6854 datasheet, "Resets the following control bits: Transmit Abort, RTS, Loop Mode, and Loop On-Line/DTR." So the moment the loopback test resets ADLC B, CR3 bit 7 is cleared – and the LED comes on. It stays on for the rest of the test pass, because no later code in the pass writes CR3 again.

A "normal" self-test pass therefore looks like this from the LED's point of view:

| Phase                                                | Duration  | LED  |
|------------------------------------------------------|-----------|------|
| `self_test_reset_adlcs` writes `CR3 = &80`           | brief     | dark |
| ZP test, ROM checksum, RAM tests, ADLC state checks  | longer    | dark |
| `self_test_loopback_a_to_b` resets B → CR3 cleared   | brief     | lit  |
| Loopback A→B, loopback B→A, jumper-number checks     | longer    | lit  |
| Pass complete – `self_test_pass_done` toggles phase  | brief     | lit  |

The "phase toggle" at the end alternates the next pass between two paths:

- **Normal pass** (every other one): jumps to `self_test_reset_adlcs`, which writes CR3 = &80 again – *the LED goes dark for the early-tests phase, then lights again at the loopback*.
- **Alt pass** (the other one): falls through to [`self_test_alt_pass`](address:F26F@variant_1?hex) at `&F26F`, which deliberately **skips** `self_test_reset_adlcs` for ADLC B. B's CR3 stays cleared from the previous loopback reset, so the *entire* alt-pass runs with the LED lit. The alt-pass body re-runs the same sub-tests, including the loopback (which resets B again – harmlessly, since CR3 is already 0).

Over time, the operator therefore sees: short dark, long lit, short dark, long lit – an asymmetric flash whose dark fraction is roughly the duration of the early-test phase of every other pass. The Bridge's RAM and ROM tests run at 6502 speed and the loopback tests run at Econet line rate, so the precise ratio depends on the clock and on how much RAM is fitted, but the cycle is in the hundreds-of-milliseconds range – well inside what an operator perceives as a regular flash. The manual describes this as an "even mark-space ratio", which it is qualitatively even if not literally 1 : 1.

The flashing isn't the result of any explicit timer or pacing code in the self-test loop. It's an emergent property of two design choices: marking self-test entry with `CR3 = &80` to extinguish the LED, and re-using the ADLC's full-reset to re-initialise the chip for the loopback tests – which incidentally clears CR3 again. The author probably intended only the first; the second is a side-effect of the chip's reset semantics. Together they produce a more informative diagnostic ("the box is in self-test, and is making forward progress through the loopback phase") than a static lit-or-dark indicator could.


## When the self-test finds a problem

The LED gets a second job when a test fails. The self-test has two distinct failure handlers, each with its own blink pattern, chosen to give the operator as much information as the hardware state allows. Both still work after the polarity correction – the underlying mechanism is the same, only the on/off labels swap.

### `self_test_fail` – the countable blinker

Reached from every non-RAM test: ROM checksum, ADLC register-state checks, A↔B loopback checks, network-number jumper checks. The caller loads an error code (2 through 8) into `A`. The blinker sets `CR1` to enable the AC bit so subsequent writes to `adlc_a_cr2` actually hit CR3, and then loops:

1. `CR3 = &00` → LED on, ~1 s of `DEX`/`DEY` delay.
2. `CR3 = &80` → LED off, ~1 s of `DEX`/`DEY` delay.
3. Decrement pulse counter; if non-zero, back to 1.
4. After N pulses, run an 8× spacer delay – CR3 stays `&80` from step 2 throughout, so the LED is held off for ~8 s.
5. Reload pulse counter, jump back to 1.

Because the pulse cycle ends with the LED off and the spacer keeps it off, the operator sees N visible "on" flashes per burst, separated by a long dark gap:

```
  on … off … on … off  (N=2 flashes)  long dark gap   on … off … on … off …    ROM checksum fail (code 2)
  on, off ×3, long gap, …                                                       ADLC A state fail (code 3)
  …
  on, off ×8, long gap, …                                                       net_num_b ≠ 2 (code 8)
```

Each code unambiguously identifies one failed sub-test. This handler depends on a working RAM – it uses `&01` as the burst counter – so it only runs when the RAM tests have already passed.

### `ram_test_fail` – the uncountable blinker

Reached from the three RAM tests (ZP integrity, `&55`/`&AA` pattern, incrementing-byte pattern). By definition, if one of these has failed, *RAM cannot be trusted* – which means no counting loop can work, because any counter variable is held in RAM. This handler therefore cannot count.

Instead, it generates its pacing from a sequence of `DEC abs,X` instructions that read-modify-write bytes in the ROM itself. Writes to ROM are silently ignored, but the CPU still spends the full five-cycle read-modify-write time on each one. A loop of seven such instructions followed by `DEX` / `DEY` runs entirely from the CPU registers, touching RAM for nothing. It's not pretty, but it's a way to blink the LED when nothing else works.

The resulting pattern alternates `CR3 = &00` (LED on) and `CR3 = &80` (LED off) at a regular pace, with no spacer. It's distinctively *structureless* – the LED alternates without the gap-grouping that makes an error-code readable. The operator infers "the RAM is bad" not from counting pulses, but from the absence of a countable pattern.


## Summary of LED behaviours

Four distinct states, all encoded through a single pin on one ADLC:

| State                    | Driver                                                      | Visible behaviour                                                |
|--------------------------|-------------------------------------------------------------|------------------------------------------------------------------|
| Normal operation         | `adlc_b_full_reset` writes `CR3 = &00` once and leaves it   | LED solid lit for the life of the session                        |
| Self-test running        | `self_test_reset_adlcs` extinguishes; loopbacks re-light    | LED flashes – dark in early tests, lit in loopback-and-after     |
| Non-RAM test failed      | `self_test_fail` alternates `CR3` N times per cycle         | LED blinks countable pattern (2–8 on-pulses per burst)           |
| RAM test failed          | `ram_test_fail` alternates `CR3` with ROM-timed pacing      | LED blinks uncountable pattern                                   |

A one-pin output reused four ways – power-and-firmware-OK indicator, diagnostic-running animator, structured failure annunciator, unstructured failure annunciator. The fact that each state is unambiguous to an operator standing in front of the box owes something to the circuit designer, who gave the pin an LED, and something to the firmware author, who put the right amount of thought into both the explicit writes (`CR3 = &00` for normal, `&80` for self-test entry, the failure-blinker toggles) and the implicit consequences of the loopback test's full reset – which is what makes the healthy-self-test indicator visibly *move* rather than sitting solid like the normal-operation one.


## Cross-references

- [`adlc_b_full_reset`](address:E40A@variant_1?hex) – sets `CR3 = &00`; entered once at boot.
- [`self_test_reset_adlcs`](address:F005@variant_1?hex) – sets `CR3 = &80`; entered every "normal" self-test pass.
- [`self_test_pass_done`](address:F264@variant_1?hex) – toggles between the normal and alternate pass paths.
- [`self_test_alt_pass`](address:F26F@variant_1?hex) – deliberately skips the LED-extinguishing reset on B.
- [`self_test_loopback_a_to_b`](address:F10A@variant_1?hex) and [`self_test_loopback_b_to_a`](address:F1AB@variant_1?hex) – their `CR1 = &C0` resets are what re-light the LED mid-pass.
- [`self_test_fail`](address:F2C7@variant_1?hex) – the countable blinker.
- [`ram_test_fail`](address:F28C@variant_1?hex) – the uncountable blinker.


## External references

- [MC68B54 datasheet](https://github.com/acornaeology/acorn-econet-bridge/raw/master/docs/Motorola-MC68B54P-datasheet.pdf) – CR3 bit meanings, LOC/DTR pin polarity, and reset semantics.
- [Ian Stocks's reverse-engineered schematic](https://stardot.org.uk/forums/download/file.php?id=26508) [requires Stardot login] – the LED-anode-to-pin wiring is documented here.
- Chris Oddy's replica – independently confirms the same wiring, with `DTR` shown on the device pin and an inverting bubble on the output.
- `docs/self-test-connections.png` – scan from the Bridge service procedure showing the official self-test rig and quoting the expected LED behaviour ("flash with an even mark-space ratio" during self-test, "remain on" after a normal power cycle).
