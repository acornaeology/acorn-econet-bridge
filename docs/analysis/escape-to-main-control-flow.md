# Escape-to-main: the Bridge's cooperative error-recovery idiom

Several subroutines in the Econet Bridge ROM share a distinctive abnormal exit:

```
    pla
    pla
    jmp main_loop        ; &E051
```

The two `PLA`s pop the caller's return address off the 6502 stack, and the `JMP` jumps straight to the main Bridge loop. The routine never returns to its caller — not even to a local error handler in the caller — and everything the caller intended to do after the `JSR` is abandoned.

Four routines in the ROM use this pattern, all in the ADLC-driven communication paths:

- `wait_adlc_a_idle` (`&E6DC`) — on timeout waiting for the Rx Idle bit
- `wait_adlc_b_idle` (`&E690`) — on timeout waiting for the Rx Idle bit
- `transmit_frame_a` (`&E517`) — on unexpected SR1 state during TX
- `transmit_frame_b` (`&E4C0`) — on unexpected SR1 state during TX

Together they are called from roughly twenty sites. Every one of those sites must be written on the assumption that the `JSR` may not return.


## What the idiom is

In a conventional 6502 subroutine, the `JSR` pushes a return address and the `RTS` pops it. Error handling then usually takes one of three forms:

- **Status-flag convention.** The subroutine sets C or Z on the way out, and the caller branches on it. Cheap, but every caller has to remember to check.
- **Per-site error handler.** The subroutine returns, and the caller has `BCC some_error_path` or similar immediately after the `JSR`. Flexible, but every caller needs its own error path.
- **Single shared error handler.** The subroutine takes an abnormal exit that always ends up in the same place. Cheapest at the call site (nothing at all), but the convention has to be known and agreed throughout the codebase.

The Bridge picks the third. The `PLA/PLA/JMP main_loop` is a cooperative recovery jump — it collapses any in-flight operation back to the dispatcher, no matter how deep the call is. The main loop will start its next cycle from a clean slate (both ADLCs re-armed, state variables reset by the loop header), and whatever the escaping routine was trying to accomplish is simply not finished.

This is, in spirit, a `longjmp` — but without a buffer, without stack unwinding, without any setup cost. The 6502's flat stack and the Bridge's single-level call structure mean the implementation fits in three instructions.


## Why it works here

The technique is only safe because two invariants hold:

1. **The call depth at escape time is always one.** The stack always has exactly the caller's return address on top, because the escaping routine never calls into something that itself might escape, and its callers always invoke it from positions where no deeper return addresses are stacked. Two `PLA`s are sufficient; there are no nested returns to worry about.
2. **The main loop re-initialises everything the escape might have left dangling.** The ADLCs are re-armed by the main-loop header (`&E051-&E078`); the TX buffer pointer is reset on successful completion by the surviving routines; no state is "half-written" in a way that would trip up the next iteration.

The first invariant is enforced by the coding discipline of the ROM rather than by hardware, and it narrows the design space. Any routine that both (a) might escape, and (b) calls another routine that might escape, would break the pattern. A quick inspection confirms that the four escaping routines above never call into each other at escape-relevant points. The discipline is there.

The second invariant is what makes the abandoned work tolerable. An incomplete transmit leaves the ADLC in a slightly unexpected state, but the main-loop header explicitly clears AP/IRQ status and re-arms CR1 and CR2 on both chips. Anything subtle enough to survive that — a half-filled TX FIFO, an unacknowledged interrupt — is handled before the first poll of the next cycle.


## What it means for the code

For every `JSR wait_adlc_?_idle` and every `JSR transmit_frame_*` in the ROM, the caller's instructions _after_ the `JSR` are conditional on non-escape: they execute only when the subroutine returns normally. Reading the ROM as though `JSR` is always followed by "normal control flow" will mislead you on timeout paths.

In the reset sequence, for example:

```
    jsr build_announce_b
    jsr wait_adlc_a_idle      ; may not return
    jsr transmit_frame_a           ; may not return
    lda station_id_a               ; reached only if both returned
    sta tx_data0
    ...
```

If `wait_adlc_a_idle` times out because the line never goes quiet within ~2 s (another station is hogging the network), the Bridge simply enters the main loop without ever transmitting the side-A announcement, and without patching `tx_data0` for the side-B transmission. It also never reaches the side-B transmission. The main loop eventually re-attempts the announcement itself via the periodic-re-announce mechanism controlled by `announce_flag` / `announce_tmr_*`. That re-announce path is the recovery.

This is a design that trades per-site clarity for global simplicity. Individual call sites are terse to the point of being misleading; the recovery logic lives entirely in one place. Once you know to read `JSR wait_adlc_?_idle` as "try this, or fall back to the main loop", the ROM becomes very compact indeed.


## Contrast with a naive implementation

A caller written without the escape convention would need something like:

```
    jsr wait_adlc_a_idle
    bcs poll_failed                ; status-flag-based error
    jsr transmit_frame_a
    bcs tx_failed
    ...
poll_failed:
    jmp main_loop
tx_failed:
    jmp main_loop
```

Four extra instructions per call site, and a branch-on-status convention to uphold in each subroutine. The Bridge's twenty call sites would cost roughly eighty bytes of ROM. The `PLA/PLA/JMP` convention costs three bytes at each escape point (four sites, twelve bytes total) plus zero at every call site. Against a fixed 8 KiB ROM budget, which had to accommodate two full ADLC drivers, a bridge protocol, a RAM sizer, a self-test, and routing state, that's a meaningful saving — especially when the "error" conditions (timeout, unexpected ADLC state) are themselves infrequent and the recovery is always the same.


## Cross-references

- `wait_adlc_a_idle` (`&E6DC`) and `wait_adlc_b_idle` (`&E690`) in the disassembly.
- `transmit_frame_a` (`&E517`) and `transmit_frame_b` (`&E4C0`) — same escape pattern guarding the TX path.
- `main_loop` at `&E051` — reached by JMP from all four escaping routines plus ten other sites.
