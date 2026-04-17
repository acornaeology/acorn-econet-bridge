; Memory locations
l0000           = &0000
l0001           = &0001
l0002           = &0002
l0003           = &0003
mem_ptr_lo      = &0080
mem_ptr_hi      = &0081
top_ram_page    = &0082
tx_end_lo       = &0200
tx_end_hi       = &0201
ctr24_lo        = &0214
ctr24_mid       = &0215
ctr24_hi        = &0216
rx_len          = &0228
announce_flag   = &0229
announce_tmr_lo = &022a
announce_tmr_hi = &022b
announce_count  = &022c
rx_dst_stn      = &023c
rx_dst_net      = &023d
rx_src_stn      = &023e
rx_src_net      = &023f
rx_ctrl         = &0240
rx_port         = &0241
rx_query_port   = &0248
rx_query_net    = &0249
reachable_via_b = &025a
reachable_via_a = &035a
tx_dst_stn      = &045a
tx_dst_net      = &045b
tx_src_stn      = &045c
tx_src_net      = &045d
tx_ctrl         = &045e
tx_port         = &045f
tx_data0        = &0460
net_num_a       = &c000
adlc_a_cr1      = &c800
adlc_a_cr2      = &c801
adlc_a_tx       = &c802
adlc_a_tx2      = &c803
net_num_b       = &d000
adlc_b_cr1      = &d800
adlc_b_cr2      = &d801
adlc_b_tx       = &d802
adlc_b_tx2      = &d803

    org &e000

; &e000 referenced 7 times by &f2a9, &f2ac, &f2af, &f2b2, &f2b5, &f2b8, &f2bb
.pydis_start
.reset
    cli                                                               ; e000: 58          X
    cld                                                               ; e001: d8          .
    jsr init_reachable_nets                                           ; e002: 20 24 e4     $.
    jsr adlc_a_full_reset                                             ; e005: 20 f0 e3     ..
    jsr adlc_b_full_reset                                             ; e008: 20 0a e4     ..
; ***************************************************************************************
; Scan pages from &1800 upward; record top of RAM
; 
; Probes pages upward from &1800 by writing &AA and &55 patterns
; through mem_ptr_lo/mem_ptr_hi (&80/&81) and verifying each. The
; highest page that verifies is stored in top_ram_page (&82), used
; downstream by workspace initialisation. The Bridge can be built
; with either one 8 KiB 6264 chip or four 2 KiB 6116 chips (chosen
; by soldered links), so RAM size must be discovered at power-on.
; 
; The routine looks like a textbook two-pattern memory test but is
; considerably more robust than a naive STA/LDA/CMP would be. Three
; independent mechanisms have to fail simultaneously for it to
; report RAM where none exists:
; 
;   1. The INC on zero-page &00 between each write and its matching
;      read is an anti-bus-residue defence. When the 6502 writes to
;      an unmapped address, no chip latches the value, but the data
;      bus capacitance can hold the written byte long enough for
;      the subsequent LDA to sample its own ghost. INC $00 is a
;      read-modify-write that drives the data bus three times with
;      values unrelated to the test pattern (the cycle-4 dummy
;      write is a classic NMOS 6502 quirk that is exploited here),
;      clobbering any residue of &AA or &55.
; 
;   2. The choice of &00 specifically is an alias tripwire. If the
;      address decoder is miswired and the target address aliases
;      into zero page, the obvious alias landing point is &00 — so
;      disturbing &00 between write and read forces any alias-based
;      false-positive to fail the CMP.
; 
;   3. The two patterns &AA and &55 are bitwise complements: a
;      stuck bit is detected on whichever pattern it contradicts,
;      and a single-value bus residue cannot spoof both checks
;      simultaneously.
; 
; See docs/analysis/ram-test-anti-aliasing.md for the full
; cycle-level analysis.
; Y = 0 (indirect offset, used throughout)
.ram_test
    ldy #0                                                            ; e00b: a0 00       ..
; mem_ptr_lo = 0 (pages tested are page-aligned)
    sty mem_ptr_lo                                                    ; e00d: 84 80       ..
; mem_ptr_hi starts at &17; INC makes first test &18
    lda #&17                                                          ; e00f: a9 17       ..
    sta mem_ptr_hi                                                    ; e011: 85 81       ..
; Advance to next page
; &e013 referenced 1 time by &e02b
.ram_test_loop
    inc mem_ptr_hi                                                    ; e013: e6 81       ..
; Pattern 1: &AA (1010_1010)
    lda #&aa                                                          ; e015: a9 aa       ..
    sta (mem_ptr_lo),y                                                ; e017: 91 80       ..
; Disturb ZP &00 -- defeat data-bus residue aliasing
    inc l0000                                                         ; e019: e6 00       ..
; Read back pattern 1
    lda (mem_ptr_lo),y                                                ; e01b: b1 80       ..
    cmp #&aa                                                          ; e01d: c9 aa       ..
; Pattern 1 mismatch -- end of RAM
    bne ram_test_done                                                 ; e01f: d0 0c       ..
; Pattern 2: &55 (0101_0101)
    lda #&55 ; 'U'                                                    ; e021: a9 55       .U
    sta (mem_ptr_lo),y                                                ; e023: 91 80       ..
; Disturb ZP &00 again
    inc l0000                                                         ; e025: e6 00       ..
; Read back pattern 2
    lda (mem_ptr_lo),y                                                ; e027: b1 80       ..
    cmp #&55 ; 'U'                                                    ; e029: c9 55       .U
; Both patterns verified -- try next page
    beq ram_test_loop                                                 ; e02b: f0 e6       ..
; Back off: last-probed page did not verify
; &e02d referenced 1 time by &e01f
.ram_test_done
    dec mem_ptr_hi                                                    ; e02d: c6 81       ..
; Save top-of-RAM page to &82 for later use
    lda mem_ptr_hi                                                    ; e02f: a5 81       ..
    sta top_ram_page                                                  ; e031: 85 82       ..
; Clear &0229 (flag, purpose TBD)
    lda #0                                                            ; e033: a9 00       ..
    sta announce_flag                                                 ; e035: 8d 29 02    .).
    jsr build_announce_b                                              ; e038: 20 58 e4     X.
    jsr wait_adlc_a_idle                                              ; e03b: 20 dc e6     ..
    jsr transmit_frame_a                                              ; e03e: 20 17 e5     ..
    lda net_num_a                                                     ; e041: ad 00 c0    ...
    sta tx_data0                                                      ; e044: 8d 60 04    .`.
    lda #4                                                            ; e047: a9 04       ..
    sta mem_ptr_hi                                                    ; e049: 85 81       ..
    jsr wait_adlc_b_idle                                              ; e04b: 20 90 e6     ..
    jsr transmit_frame_b                                              ; e04e: 20 c0 e4     ..
; ***************************************************************************************
; Main Bridge loop: re-arm ADLCs, poll for frames, re-announce
; 
; The Bridge's continuous-operation entry point. Reached by fall-
; through from the reset handler once startup completes, and by JMP
; from fourteen other sites — every routine that takes an "escape to
; main" path (wait_adlc_a_idle, transmit_frame_a/b, etc.) lands
; here, so main_loop is the anchor of every packet-processing cycle.
; 
; The header (&E051-&E078) forces each ADLC into a known RX-listening
; state: if SR2 bit 0 or 7 (AP or RDA) is already set from a partial
; or aborted previous operation, CR1 is cycled through &C2 (reset TX,
; leave RX running) before setting it to &82 (TX in reset, RX IRQs
; enabled). CR2 is set to &67 — the standard listen-mode value used
; throughout the firmware.
; 
; The inner poll loop at main_loop_poll (&E079) tests SR1 bit 7 (IRQ
; summary) on each ADLC in turn, with side B checked first. If either
; chip has a pending IRQ, control jumps straight to the corresponding
; frame handler; otherwise the idle path at main_loop_idle (&E089)
; runs the periodic re-announcement.
; 
; The re-announce scheme uses three bytes of workspace:
; 
;   announce_flag   enables re-announce (bit 7 additionally selects
;                   which side the re-announce goes out on)
;   announce_tmr_   16-bit countdown, decremented every idle-path
;     lo/hi         iteration; zero triggers the re-announce
;   announce_count  remaining re-announce cycles; when this hits
;                   zero, announce_flag is cleared and re-announce
;                   stops until something else re-enables it
; 
; The re-announce path (&E098) rebuilds the announcement frame, sets
; tx_ctrl to &81 (distinguishing it from the reset-time &80 first
; announcement), then dispatches to side A or side B based on
; announce_flag bit 7. The timer is re-armed to &8000 (32768 idle
; iterations) after each announce, giving a roughly constant cadence
; regardless of how busy the ADLCs are with other traffic.
; Check ADLC A for stale AP/RDA from previous activity
; &e051 referenced 14 times by &e0bf, &e0c7, &e13c, &e1d3, &e260, &e2bd, &e354, &e3e1, &e4d6, &e52d, &e5b3, &e644, &e6d0, &e71c
.main_loop
    lda adlc_a_cr2                                                    ; e051: ad 01 c8    ...
    and #&81                                                          ; e054: 29 81       ).
    beq ce05d                                                         ; e056: f0 05       ..
; Reset A's TX path but leave RX running
    lda #&c2                                                          ; e058: a9 c2       ..
    sta adlc_a_cr1                                                    ; e05a: 8d 00 c8    ...
; Arm CR1 A = &82: TX reset, RX IRQ enabled
; &e05d referenced 1 time by &e056
.ce05d
    ldx #&82                                                          ; e05d: a2 82       ..
    stx adlc_a_cr1                                                    ; e05f: 8e 00 c8    ...
; Arm CR2 A = &67: standard listen-mode config
    ldy #&67 ; 'g'                                                    ; e062: a0 67       .g
    sty adlc_a_cr2                                                    ; e064: 8c 01 c8    ...
; Same stale-state check for ADLC B
    lda adlc_b_cr2                                                    ; e067: ad 01 d8    ...
    and #&81                                                          ; e06a: 29 81       ).
    beq ce073                                                         ; e06c: f0 05       ..
    lda #&c2                                                          ; e06e: a9 c2       ..
    sta adlc_b_cr1                                                    ; e070: 8d 00 d8    ...
; Arm CR1 B = &82 and CR2 B = &67
; &e073 referenced 1 time by &e06c
.ce073
    stx adlc_b_cr1                                                    ; e073: 8e 00 d8    ...
    sty adlc_b_cr2                                                    ; e076: 8c 01 d8    ...
; Test SR1 bit 7 on B (IRQ summary)
; &e079 referenced 5 times by &e08c, &e091, &e096, &e144, &e2c5
.main_loop_poll
    bit adlc_b_cr1                                                    ; e079: 2c 00 d8    ,..
; No IRQ on B, check A
    bpl ce081                                                         ; e07c: 10 03       ..
; B IRQ: hand off to side-B frame handler
    jmp rx_frame_b                                                    ; e07e: 4c 63 e2    Lc.

; Test SR1 bit 7 on A (IRQ summary)
; &e081 referenced 1 time by &e07c
.ce081
    bit adlc_a_cr1                                                    ; e081: 2c 00 c8    ,..
; No IRQ on A, drop to idle path
    bpl main_loop_idle                                                ; e084: 10 03       ..
; A IRQ: hand off to side-A frame handler
    jmp rx_frame_a                                                    ; e086: 4c e2 e0    L..

; Re-announce enabled?
; &e089 referenced 1 time by &e084
.main_loop_idle
    lda announce_flag                                                 ; e089: ad 29 02    .).
; No: go back to polling the ADLCs
    beq main_loop_poll                                                ; e08c: f0 eb       ..
; Yes: decrement 16-bit re-announce timer
    dec announce_tmr_lo                                               ; e08e: ce 2a 02    .*.
; Still ticking, back to poll
    bne main_loop_poll                                                ; e091: d0 e6       ..
; LSB wrapped, tick MSB too
    dec announce_tmr_hi                                               ; e093: ce 2b 02    .+.
; Still ticking, back to poll
    bne main_loop_poll                                                ; e096: d0 e1       ..
; ***************************************************************************************
; Periodic re-announcement of the bridge on one side
; 
; Reached from the idle path once the 16-bit announce_tmr has
; ticked down to zero. Rebuilds the announcement frame via
; build_announce_b (same template used at reset), then patches
; tx_ctrl to &81 — the &80 value written by build_announce_b is
; the initial/first-broadcast control byte, while &81 is the
; re-announce variant. The receiving stations can presumably
; distinguish first-seen-bridge from follow-up announcements by
; this single bit.
; 
; Which side to transmit on is selected by announce_flag bit 7:
; 
;   bit 7 clear (flag = 1..&7F)  ->  transmit via ADLC A (side A)
;   bit 7 set   (flag = &80..FF) ->  transmit via ADLC B (side B,
;                                    after patching tx_data0 with
;                                    net_num_a, mirroring the
;                                    reset-time dual-broadcast)
; 
; Each visit decrements announce_count. If it hits zero, announce_
; flag is cleared and periodic re-announce stops (re_announce_done).
; Otherwise the timer is re-armed to &8000 and control returns to
; main_loop (re_announce_rearm).
; 
; Before transmitting on one side, the routine resets the OTHER
; ADLC's TX path (CR1 = &C2) — this prevents the opposite side from
; accidentally transmitting a collision during our operation.
; Rebuild the frame template (dst=FF, ctrl=&80, ...)
.re_announce
    jsr build_announce_b                                              ; e098: 20 58 e4     X.
; Patch ctrl = &81 (re-announce variant)
    lda #&81                                                          ; e09b: a9 81       ..
    sta tx_ctrl                                                       ; e09d: 8d 5e 04    .^.
; Test announce_flag bit 7: which side?
    bit announce_flag                                                 ; e0a0: 2c 29 02    ,).
; Bit 7 set -> transmit via side B
    bmi re_announce_side_b                                            ; e0a3: 30 25       0%
; Side A path: reset B's TX first (no collision)
    lda #&c2                                                          ; e0a5: a9 c2       ..
    sta adlc_b_cr1                                                    ; e0a7: 8d 00 d8    ...
; Wait for A's line to go idle then transmit
    jsr wait_adlc_a_idle                                              ; e0aa: 20 dc e6     ..
    jsr transmit_frame_a                                              ; e0ad: 20 17 e5     ..
; Count this announce; stop if exhausted
    dec announce_count                                                ; e0b0: ce 2c 02    .,.
    beq re_announce_done                                              ; e0b3: f0 0d       ..
; Re-arm timer to &8000 (32K idle iterations)
; &e0b5 referenced 1 time by &e0e0
.re_announce_rearm
    lda #&80                                                          ; e0b5: a9 80       ..
    sta announce_tmr_hi                                               ; e0b7: 8d 2b 02    .+.
    lda #0                                                            ; e0ba: a9 00       ..
    sta announce_tmr_lo                                               ; e0bc: 8d 2a 02    .*.
; Back to main loop
    jmp main_loop                                                     ; e0bf: 4c 51 e0    LQ.

; announce_count exhausted: disable re-announce
; &e0c2 referenced 2 times by &e0b3, &e0de
.re_announce_done
    lda #0                                                            ; e0c2: a9 00       ..
    sta announce_flag                                                 ; e0c4: 8d 29 02    .).
; Back to main loop
    jmp main_loop                                                     ; e0c7: 4c 51 e0    LQ.

; Side B path: patch tx_data0 for side-B broadcast
; &e0ca referenced 1 time by &e0a3
.re_announce_side_b
    lda net_num_a                                                     ; e0ca: ad 00 c0    ...
    sta tx_data0                                                      ; e0cd: 8d 60 04    .`.
; Reset A's TX first (mirror of side-A path)
    lda #&c2                                                          ; e0d0: a9 c2       ..
    sta adlc_a_cr1                                                    ; e0d2: 8d 00 c8    ...
; Wait for B's line to go idle then transmit
    jsr wait_adlc_b_idle                                              ; e0d5: 20 90 e6     ..
    jsr transmit_frame_b                                              ; e0d8: 20 c0 e4     ..
; Count this announce; stop if exhausted
    dec announce_count                                                ; e0db: ce 2c 02    .,.
    beq re_announce_done                                              ; e0de: f0 e2       ..
; Not exhausted -> re_announce_rearm (ALWAYS branch)
    bne re_announce_rearm                                             ; e0e0: d0 d3       ..             ; ALWAYS branch

; ***************************************************************************************
; Drain and dispatch an inbound frame on ADLC A
; 
; Reached from main_loop_poll when ADLC A raises SR1 bit 7. Drains
; the incoming scout frame from the RX FIFO into the rx_* buffer at
; &023C-&024F, runs two levels of filtering, and then dispatches on
; the control byte to per-message handlers.
; 
; Filtering stage 1 — addressing:
; 
;   Expect SR2 bit 0 (AP: Address Present) -- if missing, bail to
;   main_loop (spurious IRQ).
; 
;   Read byte 0 (rx_dst_stn) and byte 1 (rx_dst_net). If rx_dst_net
;   is zero (local net) or reachable_via_b[rx_dst_net] is zero (unknown
;   network), jump to rx_a_not_for_us (&E13F): ignore the frame,
;   re-listen, drop back to main_loop_poll without a full main_loop
;   re-init.
; 
; Draining:
; 
;   Read the rest of the frame in byte-pairs into &023C+Y up to Y=20
;   (the Bridge only keeps the first 20 bytes). After the drain,
;   force CR1=0 and CR2=&84 to halt the chip and test SR2 bit 1
;   (FV, Frame Valid). If FV is clear, the frame was corrupt or
;   short -- bail to main_loop. If SR2 bit 7 (RDA) is also set,
;   read one trailing byte.
; 
; Filtering stage 2 — broadcast check:
; 
;   Only frames with dst_stn == dst_net == &FF (full broadcast)
;   proceed to the bridge-protocol dispatcher. Everything else
;   falls to rx_a_forward (&E208), the cross-network forwarding
;   path (not yet analysed).
; 
; Dispatch on rx_ctrl (after verifying rx_port == &9C = bridge
; protocol):
; 
;   &80  ->  rx_a_handle_80  (&E1D6) - initial bridge announcement
;   &81  ->  rx_a_handle_81  (&E1EE) - re-announcement
;   &82  ->  rx_a_handle_82  (&E19D) - bridge query (tentative)
;   &83  ->  rx_a_handle_83  (&E195) - bridge query, known-station
;   other ->  rx_a_forward   (&E208) - forward or discard
; 
; The side-B handler at &E263 is the mirror of this routine.
; A = &01: mask SR2 bit 0 (AP: Address Present)
; &e0e2 referenced 1 time by &e086
.rx_frame_a
    lda #1                                                            ; e0e2: a9 01       ..
    bit adlc_a_cr2                                                    ; e0e4: 2c 01 c8    ,..
; AP missing -> spurious IRQ, bail
    beq rx_frame_a_bail                                               ; e0e7: f0 53       .S
; Read byte 0: destination station
    lda adlc_a_tx                                                     ; e0e9: ad 02 c8    ...
    sta rx_dst_stn                                                    ; e0ec: 8d 3c 02    .<.
; Wait for second IRQ: next byte ready
    jsr wait_adlc_a_irq                                               ; e0ef: 20 e4 e3     ..
    bit adlc_a_cr2                                                    ; e0f2: 2c 01 c8    ,..
; No second IRQ -> frame is truncated, bail
    bpl rx_frame_a_bail                                               ; e0f5: 10 45       .E
; Read byte 1: destination network
    ldy adlc_a_tx                                                     ; e0f7: ac 02 c8    ...
; dst_net == 0 (local net) -> not for us
    beq rx_a_not_for_us                                               ; e0fa: f0 43       .C
; dst_net not known in reachable_via_b -> not for us
    lda reachable_via_b,y                                             ; e0fc: b9 5a 02    .Z.
    beq rx_a_not_for_us                                               ; e0ff: f0 3e       .>
    sty rx_dst_net                                                    ; e101: 8c 3d 02    .=.
; Y = 2: start of pair-drain loop
    ldy #2                                                            ; e104: a0 02       ..
; Wait for next FIFO IRQ
; &e106 referenced 1 time by &e11e
.rx_frame_a_drain
    jsr wait_adlc_a_irq                                               ; e106: 20 e4 e3     ..
    bit adlc_a_cr2                                                    ; e109: 2c 01 c8    ,..
; IRQ cleared -> end of frame body
    bpl rx_frame_a_end                                                ; e10c: 10 12       ..
; Read byte Y
    lda adlc_a_tx                                                     ; e10e: ad 02 c8    ...
    sta rx_dst_stn,y                                                  ; e111: 99 3c 02    .<.
    iny                                                               ; e114: c8          .
; Read byte Y+1 (pair for throughput)
    lda adlc_a_tx                                                     ; e115: ad 02 c8    ...
    sta rx_dst_stn,y                                                  ; e118: 99 3c 02    .<.
    iny                                                               ; e11b: c8          .
; Stop at 20 bytes (header + 14 payload)
    cpy #&14                                                          ; e11c: c0 14       ..
    bcc rx_frame_a_drain                                              ; e11e: 90 e6       ..
; Halt the ADLC: CR1=0, CR2=&84
; &e120 referenced 1 time by &e10c
.rx_frame_a_end
    lda #0                                                            ; e120: a9 00       ..
    sta adlc_a_cr1                                                    ; e122: 8d 00 c8    ...
    lda #&84                                                          ; e125: a9 84       ..
    sta adlc_a_cr2                                                    ; e127: 8d 01 c8    ...
; A = &02: mask SR2 bit 1 (FV: Frame Valid)
    lda #2                                                            ; e12a: a9 02       ..
    bit adlc_a_cr2                                                    ; e12c: 2c 01 c8    ,..
; No FV -> frame corrupt/short, bail
    beq rx_frame_a_bail                                               ; e12f: f0 0b       ..
; FV set but no RDA -> frame done, process it
    bpl rx_frame_a_dispatch                                           ; e131: 10 17       ..
; FV + RDA: one trailing byte to drain
    lda adlc_a_tx                                                     ; e133: ad 02 c8    ...
    sta rx_dst_stn,y                                                  ; e136: 99 3c 02    .<.
    iny                                                               ; e139: c8          .
    bne rx_frame_a_dispatch                                           ; e13a: d0 0e       ..
; Bail: return to main_loop
; &e13c referenced 4 times by &e0e7, &e0f5, &e12f, &e14f
.rx_frame_a_bail
    jmp main_loop                                                     ; e13c: 4c 51 e0    LQ.

; Re-listen with CR1=&A2 (RX on, IRQ enabled)
; &e13f referenced 2 times by &e0fa, &e0ff
.rx_a_not_for_us
    lda #&a2                                                          ; e13f: a9 a2       ..
    sta adlc_a_cr1                                                    ; e141: 8d 00 c8    ...
; Back to poll (skip main_loop re-arm)
    jmp main_loop_poll                                                ; e144: 4c 79 e0    Ly.

; Dispatched to rx_a_forward at &E208
; &e147 referenced 2 times by &e171, &e180
.rx_a_to_forward
    jmp rx_a_forward                                                  ; e147: 4c 08 e2    L..

; Save final byte count as rx_len
; &e14a referenced 2 times by &e131, &e13a
.rx_frame_a_dispatch
    sty rx_len                                                        ; e14a: 8c 28 02    .(.
; Need >= 6 bytes for a valid scout header
    cpy #6                                                            ; e14d: c0 06       ..
    bcc rx_frame_a_bail                                               ; e14f: 90 eb       ..
; Lazy-init rx_src_net if zero
    lda rx_src_net                                                    ; e151: ad 3f 02    .?.
    bne ce15c                                                         ; e154: d0 06       ..
; Default src_net to net_num_a
    lda net_num_a                                                     ; e156: ad 00 c0    ...
    sta rx_src_net                                                    ; e159: 8d 3f 02    .?.
; Is rx_dst_net addressing side B (= our B station)?
; &e15c referenced 1 time by &e154
.ce15c
    lda net_num_b                                                     ; e15c: ad 00 d0    ...
    cmp rx_dst_net                                                    ; e15f: cd 3d 02    .=.
    bne ce169                                                         ; e162: d0 05       ..
; Yes: normalise rx_dst_net to 0 (local on B)
    lda #0                                                            ; e164: a9 00       ..
    sta rx_dst_net                                                    ; e166: 8d 3d 02    .=.
; Broadcast test: both dst bytes == &FF?
; &e169 referenced 1 time by &e162
.ce169
    lda rx_dst_stn                                                    ; e169: ad 3c 02    .<.
    and rx_dst_net                                                    ; e16c: 2d 3d 02    -=.
    cmp #&ff                                                          ; e16f: c9 ff       ..
; Not broadcast -> forward path
    bne rx_a_to_forward                                               ; e171: d0 d4       ..
; Broadcast: re-arm A's listen mode
    jsr adlc_a_listen                                                 ; e173: 20 ff e3     ..
    lda #&c2                                                          ; e176: a9 c2       ..
    sta adlc_a_cr1                                                    ; e178: 8d 00 c8    ...
    lda rx_port                                                       ; e17b: ad 41 02    .A.
; Bridge-protocol port (&9C)?
    cmp #&9c                                                          ; e17e: c9 9c       ..
; Not bridge protocol -> forward
    bne rx_a_to_forward                                               ; e180: d0 c5       ..
; Dispatch on rx_ctrl
    lda rx_ctrl                                                       ; e182: ad 40 02    .@.
; &81 -> re-announcement handler
    cmp #&81                                                          ; e185: c9 81       ..
    beq rx_a_handle_81                                                ; e187: f0 65       .e
; &80 -> initial announcement handler
    cmp #&80                                                          ; e189: c9 80       ..
    beq rx_a_handle_80                                                ; e18b: f0 49       .I
; &82 -> bridge query (shares &83 path)
    cmp #&82                                                          ; e18d: c9 82       ..
    beq rx_a_handle_82                                                ; e18f: f0 0c       ..
; &83 -> bridge query, known-station path
    cmp #&83                                                          ; e191: c9 83       ..
    bne rx_a_forward                                                  ; e193: d0 73       .s
; Station Y known in reachable_via_b?
; ***************************************************************************************
; Side-A IsNet query (ctrl=&83): targeted network lookup
; 
; Called when a received frame on side A is broadcast + port=&9C +
; ctrl=&83. In JGH's BRIDGE.SRC this query type is named "IsNet" —
; the querier is asking "can you reach network X?", where X is the
; byte at offset 13 of the payload (rx_query_net).
; 
; Consults reachable_via_b[rx_query_net]. If the entry is zero, we
; have no route to that network so the query is silently dropped
; (JMP main_loop via &E1D3). If non-zero, falls through to the
; shared response body at rx_a_handle_82 to transmit the reply --
; so IsNet is effectively WhatNet with an up-front routing filter.
; Y = rx_query_net: network being queried
.rx_a_handle_83
    ldy rx_query_net                                                  ; e195: ac 49 02    .I.
; Look up in reachable_via_b
    lda reachable_via_b,y                                             ; e198: b9 5a 02    .Z.
; Unknown -> skip, back to main loop
; Unknown network -> silently drop the query
    beq ce1d3                                                         ; e19b: f0 36       .6
; ***************************************************************************************
; Side-A WhatNet query (ctrl=&82); also the IsNet response path
; 
; Called when a received frame on side A is broadcast + port=&9C +
; ctrl=&82 (named "WhatNet" in JGH's BRIDGE.SRC — a general bridge
; query asking "which networks do you reach?"), or when
; rx_a_handle_83 has verified that a specific IsNet queried network
; is in fact reachable via side B and is re-using this response
; path.
; 
; The response is a complete four-way handshake transaction, which
; the Bridge drives from the responder side as two transmissions
; (scout, then data) with an inbound ACK after each:
; 
;   1. Build a reply-scout template via build_query_response,
;      addressed back to the querier on its local network with
;      tx_src_net patched to our net_num_b.
; 
;   2. Stagger the scout transmission via stagger_delay, seeded
;      from net_num_b. Multiple bridges on the same segment will
;      all react to a broadcast query, and without the stagger
;      their responses would overlap on the wire; seeding from the
;      network number gives each bridge a deterministic but
;      distinct delay.
; 
;   3. CSMA, transmit the scout, then handshake_rx_a to receive
;      the scout-ACK.
; 
;   4. Rebuild the frame via build_query_response again -- this
;      time to be a *data* frame following the scout we just
;      exchanged, not a new scout. The patches that follow populate
;      the first two payload bytes of that data frame (at the byte
;      positions labelled tx_ctrl and tx_port, but those names
;      refer to scout semantics -- in a data frame those slots are
;      payload, not header, and the bytes are:
; 
;         data0 = net_num_a        ... the Bridge's side-A network
;         data1 = rx_query_net     ... echo of the queried network
; 
;      The answer thus consists of the dst/src quad plus two
;      payload bytes, packed into the smallest Econet frame that
;      can carry it.
; 
;   5. Transmit the data frame, then handshake_rx_a for the final
;      data-ACK. JMP main_loop on completion.
; 
; Either handshake_rx_a call can escape to main_loop if the querier
; doesn't keep up the handshake, aborting the conversation cleanly.
; Re-arm A for listen after the received query
; &e19d referenced 1 time by &e18f
.rx_a_handle_82
    jsr adlc_a_listen                                                 ; e19d: 20 ff e3     ..
; Build reply-scout template (unicast to querier)
    jsr build_query_response                                          ; e1a0: 20 8d e4     ..
; Patch src_net with our B-side network number
    lda net_num_b                                                     ; e1a3: ad 00 d0    ...
    sta tx_src_net                                                    ; e1a6: 8d 5d 04    .].
; Seed stagger counter from net_num_b
    sta ctr24_lo                                                      ; e1a9: 8d 14 02    ...
; Delay before transmit -- collision avoidance
    jsr stagger_delay                                                 ; e1ac: 20 48 e4     H.
; CSMA on A
    jsr wait_adlc_a_idle                                              ; e1af: 20 dc e6     ..
; Transmit reply scout (dst = querier)
    jsr transmit_frame_a                                              ; e1b2: 20 17 e5     ..
; Receive scout-ACK from querier
    jsr handshake_rx_a                                                ; e1b5: 20 6e e5     n.
; Rebuild buffer; now populating it as a data frame
    jsr build_query_response                                          ; e1b8: 20 8d e4     ..
    lda net_num_b                                                     ; e1bb: ad 00 d0    ...
    sta tx_src_net                                                    ; e1be: 8d 5d 04    .].
; Data payload byte 0 = net_num_a
    lda net_num_a                                                     ; e1c1: ad 00 c0    ...
    sta tx_ctrl                                                       ; e1c4: 8d 5e 04    .^.
; Data payload byte 1 = echo of queried network
    lda rx_query_net                                                  ; e1c7: ad 49 02    .I.
    sta tx_port                                                       ; e1ca: 8d 5f 04    ._.
; Transmit response data frame
    jsr transmit_frame_a                                              ; e1cd: 20 17 e5     ..
; Receive final data-ACK
    jsr handshake_rx_a                                                ; e1d0: 20 6e e5     n.
; &e1d3 referenced 1 time by &e19b
.ce1d3
    jmp main_loop                                                     ; e1d3: 4c 51 e0    LQ.

; ***************************************************************************************
; Side-A BridgeReset (ctrl=&80): learn topology from scratch
; 
; Called when a received frame on side A is broadcast + port=&9C +
; ctrl=&80. In JGH's BRIDGE.SRC this control byte is named
; "BridgeReset" -- a bridge on the far side is advertising a fresh
; topology, likely because it has itself just come up. We:
; 
;   1. Wipe all learned routing state via init_reachable_nets. The
;      topology may have changed non-monotonically, so accumulated
;      reachable_via_? entries are suspect and the safe move is to
;      discard them and relearn.
; 
;   2. Schedule a burst of our own re-announcements: ten cycles with
;      a staggered initial timer value seeded from net_num_b. Using
;      the local network number as the timer's phase means bridges
;      on different segments aren't all re-announcing at the same
;      millisecond. announce_flag is set to &40 (enable, bit 7
;      clear = next outbound on side A).
; 
;   3. Fall through to rx_a_handle_81 (the same payload-processing
;      loop runs for both BridgeReset and BridgeReply) to mark the
;      sender's known networks as reachable-via-A.
; Forget learned routes (topology change)
; &e1d6 referenced 1 time by &e18b
.rx_a_handle_80
    jsr init_reachable_nets                                           ; e1d6: 20 24 e4     $.
; Seed timer high byte from our B-side net number
    lda net_num_b                                                     ; e1d9: ad 00 d0    ...
    sta announce_tmr_hi                                               ; e1dc: 8d 2b 02    .+.
; Timer low byte = 0
    lda #0                                                            ; e1df: a9 00       ..
    sta announce_tmr_lo                                               ; e1e1: 8d 2a 02    .*.
; Queue 10 re-announces
    lda #&0a                                                          ; e1e4: a9 0a       ..
    sta announce_count                                                ; e1e6: 8d 2c 02    .,.
; Flag = &40 (enable, side A)
    lda #&40 ; '@'                                                    ; e1e9: a9 40       .@
    sta announce_flag                                                 ; e1eb: 8d 29 02    .).
; ***************************************************************************************
; Side-A BridgeReply (ctrl=&81): learn and re-broadcast
; 
; Reached either directly as the ctrl=&81 handler ("BridgeReply" /
; "ResetReply" in JGH's source — the re-announcement that follows
; a BridgeReset) or via fall-through from rx_a_handle_80 (which
; additionally wipes routing state before the learn loop).
; 
; Processes the announcement payload: each byte from offset 6 up
; to rx_len is a network number that the announcer says it can
; reach. Since the announcer is on side A, we can reach those
; networks via side A ourselves -- mark each in reachable_via_a.
; 
; After the learn loop, append our own net_num_a to the payload
; and bump rx_len. Falling through to rx_a_forward re-broadcasts
; the augmented frame out of ADLC B, so any bridges beyond us on
; that side hear about the announced networks plus us as one
; further hop along the route. This is classic distance-vector
; flooding.
; 
; A subtlety: JGH's BRIDGE.SRC memory-layout comments describe
; the payload as sometimes starting with the literal ASCII string
; "BRIDGE" at bytes 6-11 (in query frames). Our handler makes no
; such check -- it treats every byte from offset 6 up as a network
; number. A frame from a "newer" variant that prepended "BRIDGE"
; would have bytes &42 &52 &49 &44 &47 &45 erroneously marked as
; reachable network numbers. No evidence that any in-the-wild
; variant does this for ctrl=&80/&81; our own ROM doesn't emit the
; string in any outbound frame.
; Y = 6: start of announcement payload
; &e1ee referenced 1 time by &e187
.rx_a_handle_81
    ldy #6                                                            ; e1ee: a0 06       ..
; Read next network number from payload
; &e1f0 referenced 1 time by &e1fd
.rx_a_learn_loop
    lda rx_dst_stn,y                                                  ; e1f0: b9 3c 02    .<.
; X = network number
    tax                                                               ; e1f3: aa          .
    lda #&ff                                                          ; e1f4: a9 ff       ..
; Mark network X as reachable via side A
    sta reachable_via_a,x                                             ; e1f6: 9d 5a 03    .Z.
    iny                                                               ; e1f9: c8          .
; End of payload?
    cpy rx_len                                                        ; e1fa: cc 28 02    .(.
    bne rx_a_learn_loop                                               ; e1fd: d0 f1       ..
; Append our net_num_a to the payload
    lda net_num_a                                                     ; e1ff: ad 00 c0    ...
    sta rx_dst_stn,y                                                  ; e202: 99 3c 02    .<.
; Bump the frame length by one byte
    inc rx_len                                                        ; e205: ee 28 02    .(.
; ***************************************************************************************
; Forward an A-side frame to B, completing the 4-way handshake
; 
; Entry point for cross-network forwarding of frames received on
; side A. Reached from three places:
; 
;   * rx_a_to_forward (&E147): the A-side frame is addressed to a
;     remote station (not a full broadcast), and we have accepted
;     it via the routing filter.
;   * rx_frame_a ctrl dispatch fall-through (&E193): the frame is
;     broadcast + port &9C but has a control byte outside the
;     recognised bridge-protocol set (&80-&83).
;   * Fall-through from rx_a_handle_81 (&E207): we've learned from
;     the announcement and appended net_num_a to the payload; now
;     propagate it onward.
; 
; The routine bridges the complete Econet four-way handshake by
; alternating direct-forward, receive-on-one-side, and re-transmit:
; 
;   Stage 1 (SCOUT, A -> B): the inbound scout already sits in the
;   rx_* buffer (&023C..). Round rx_len down to even, wait for B
;   to be idle, then push the bytes directly into adlc_b_tx in
;   pairs (odd-length frames send the trailing byte as a single
;   write). Terminate by writing CR2=&3F (end-of-burst).
; 
;   Stage 2 (ACK1, B -> A): handshake_rx_b drains the receiver's
;   ACK from ADLC B into the &045A staging buffer. transmit_frame_a
;   forwards it to the originator.
; 
;   Stage 3 (DATA, A -> B): handshake_rx_a drains the sender's
;   data frame from ADLC A into &045A. transmit_frame_b forwards
;   it to the destination.
; 
;   Stage 4 (ACK2, B -> A): handshake_rx_b drains the receiver's
;   final ACK. transmit_frame_a forwards it to the originator.
; 
; Each handshake_rx_? call can escape to main_loop (PLA/PLA/JMP) if
; the expected frame doesn't arrive, cleanly aborting the bridged
; conversation without further work on either side.
; 
; The A-B-A transmit pattern that appears at the routine's tail is
; therefore the natural shape of a bridged four-way handshake when
; the initial scout came from side A: two frames travel A -> B
; (scout and data) and two travel B -> A (two ACKs).
; rx_len -> even-rounded byte count for pair loop
; &e208 referenced 2 times by &e147, &e193
.rx_a_forward
    lda rx_len                                                        ; e208: ad 28 02    .(.
; X = original rx_len (preserved for odd-fix at end)
    tax                                                               ; e20b: aa          .
    and #&fe                                                          ; e20c: 29 fe       ).
    sta rx_len                                                        ; e20e: 8d 28 02    .(.
; CSMA on side B before transmitting
    jsr wait_adlc_b_idle                                              ; e211: 20 90 e6     ..
; Y = 0: rx buffer offset
    ldy #0                                                            ; e214: a0 00       ..
; Wait for TDRA on B
; &e216 referenced 1 time by &e22f
.rx_a_forward_pair_loop
    jsr wait_adlc_b_irq                                               ; e216: 20 ea e3     ..
    bit adlc_b_cr1                                                    ; e219: 2c 00 d8    ,..
; TDRA clear -> ADLC lost sync, escape to main
    bvc rx_a_forward_done                                             ; e21c: 50 42       PB
; Send byte Y (from rx buffer) as continuation
    lda rx_dst_stn,y                                                  ; e21e: b9 3c 02    .<.
    sta adlc_b_tx                                                     ; e221: 8d 02 d8    ...
    iny                                                               ; e224: c8          .
; Send byte Y+1 (pair for throughput)
    lda rx_dst_stn,y                                                  ; e225: b9 3c 02    .<.
    sta adlc_b_tx                                                     ; e228: 8d 02 d8    ...
    iny                                                               ; e22b: c8          .
; Done at even length?
    cpy rx_len                                                        ; e22c: cc 28 02    .(.
    bcc rx_a_forward_pair_loop                                        ; e22f: 90 e5       ..
; Recover original length to check parity
    txa                                                               ; e231: 8a          .
; ROR: carry <- bit 0 (= original length was odd?)
    ror a                                                             ; e232: 6a          j
; Even -> skip trailing-byte path
    bcc rx_a_forward_ack_round                                        ; e233: 90 09       ..
; Odd-length tail: wait for TDRA
    jsr wait_adlc_b_irq                                               ; e235: 20 ea e3     ..
; ...send the final byte
    lda rx_dst_stn,y                                                  ; e238: b9 3c 02    .<.
    sta adlc_b_tx                                                     ; e23b: 8d 02 d8    ...
; CR2 = &3F: end-of-burst (scout delivered)
; &e23e referenced 1 time by &e233
.rx_a_forward_ack_round
    lda #&3f ; '?'                                                    ; e23e: a9 3f       .?
    sta adlc_b_cr2                                                    ; e240: 8d 01 d8    ...
    jsr wait_adlc_b_irq                                               ; e243: 20 ea e3     ..
; Reset mem_ptr to &045A for the handshake staging
    lda #&5a ; 'Z'                                                    ; e246: a9 5a       .Z
    sta mem_ptr_lo                                                    ; e248: 85 80       ..
    lda #4                                                            ; e24a: a9 04       ..
    sta mem_ptr_hi                                                    ; e24c: 85 81       ..
; Stage 2: receive ACK1 on B into &045A
    jsr handshake_rx_b                                                ; e24e: 20 ff e5     ..
; ...forward ACK1 to A
    jsr transmit_frame_a                                              ; e251: 20 17 e5     ..
; Stage 3: receive DATA on A into &045A
    jsr handshake_rx_a                                                ; e254: 20 6e e5     n.
; ...forward DATA to B
    jsr transmit_frame_b                                              ; e257: 20 c0 e4     ..
; Stage 4: receive ACK2 on B into &045A
    jsr handshake_rx_b                                                ; e25a: 20 ff e5     ..
; ...forward ACK2 to A
    jsr transmit_frame_a                                              ; e25d: 20 17 e5     ..
; Handshake complete -> back to main_loop
; &e260 referenced 1 time by &e21c
.rx_a_forward_done
    jmp main_loop                                                     ; e260: 4c 51 e0    LQ.

; ***************************************************************************************
; Drain and dispatch an inbound frame on ADLC B
; 
; Byte-for-byte mirror of rx_frame_a (&E0E2): same three-stage
; structure (addressing filter, drain, broadcast + bridge-protocol
; check), same control-byte dispatch, with `adlc_a_*` replaced by
; `adlc_b_*`, `reachable_via_b` by `reachable_via_a`, and the side-selector
; value swaps (`net_num_a` ↔ `net_num_b`) where appropriate.
; 
; Bridge-protocol dispatch for this side:
; 
;   &80  ->  rx_b_handle_80  (&E357) - initial bridge announcement
;   &81  ->  rx_b_handle_81  (&E36F) - re-announcement
;   &82  ->  rx_b_handle_82  (&E31E) - bridge query (shared &83 path)
;   &83  ->  rx_b_handle_83  (&E316) - bridge query, known-station
;   other ->  rx_b_forward   (&E389) - forward or discard
; 
; See rx_frame_a for the full per-instruction explanation.
; &e263 referenced 1 time by &e07e
.rx_frame_b
    lda #1                                                            ; e263: a9 01       ..
    bit adlc_b_cr2                                                    ; e265: 2c 01 d8    ,..
    beq rx_frame_b_bail                                               ; e268: f0 53       .S
    lda adlc_b_tx                                                     ; e26a: ad 02 d8    ...
    sta rx_dst_stn                                                    ; e26d: 8d 3c 02    .<.
    jsr wait_adlc_b_irq                                               ; e270: 20 ea e3     ..
    bit adlc_b_cr2                                                    ; e273: 2c 01 d8    ,..
    bpl rx_frame_b_bail                                               ; e276: 10 45       .E
    ldy adlc_b_tx                                                     ; e278: ac 02 d8    ...
    beq rx_b_not_for_us                                               ; e27b: f0 43       .C
    lda reachable_via_a,y                                             ; e27d: b9 5a 03    .Z.
    beq rx_b_not_for_us                                               ; e280: f0 3e       .>
    sty rx_dst_net                                                    ; e282: 8c 3d 02    .=.
    ldy #2                                                            ; e285: a0 02       ..
; &e287 referenced 1 time by &e29f
.rx_frame_b_drain
    jsr wait_adlc_b_irq                                               ; e287: 20 ea e3     ..
    bit adlc_b_cr2                                                    ; e28a: 2c 01 d8    ,..
    bpl rx_frame_b_end                                                ; e28d: 10 12       ..
    lda adlc_b_tx                                                     ; e28f: ad 02 d8    ...
    sta rx_dst_stn,y                                                  ; e292: 99 3c 02    .<.
    iny                                                               ; e295: c8          .
    lda adlc_b_tx                                                     ; e296: ad 02 d8    ...
    sta rx_dst_stn,y                                                  ; e299: 99 3c 02    .<.
    iny                                                               ; e29c: c8          .
    cpy #&14                                                          ; e29d: c0 14       ..
    bcc rx_frame_b_drain                                              ; e29f: 90 e6       ..
; &e2a1 referenced 1 time by &e28d
.rx_frame_b_end
    lda #0                                                            ; e2a1: a9 00       ..
    sta adlc_b_cr1                                                    ; e2a3: 8d 00 d8    ...
    lda #&84                                                          ; e2a6: a9 84       ..
    sta adlc_b_cr2                                                    ; e2a8: 8d 01 d8    ...
    lda #2                                                            ; e2ab: a9 02       ..
    bit adlc_b_cr2                                                    ; e2ad: 2c 01 d8    ,..
    beq rx_frame_b_bail                                               ; e2b0: f0 0b       ..
    bpl rx_frame_b_dispatch                                           ; e2b2: 10 17       ..
    lda adlc_b_tx                                                     ; e2b4: ad 02 d8    ...
    sta rx_dst_stn,y                                                  ; e2b7: 99 3c 02    .<.
    iny                                                               ; e2ba: c8          .
    bne rx_frame_b_dispatch                                           ; e2bb: d0 0e       ..
; &e2bd referenced 4 times by &e268, &e276, &e2b0, &e2d0
.rx_frame_b_bail
    jmp main_loop                                                     ; e2bd: 4c 51 e0    LQ.

; &e2c0 referenced 2 times by &e27b, &e280
.rx_b_not_for_us
    lda #&a2                                                          ; e2c0: a9 a2       ..
    sta adlc_b_cr1                                                    ; e2c2: 8d 00 d8    ...
    jmp main_loop_poll                                                ; e2c5: 4c 79 e0    Ly.

; &e2c8 referenced 2 times by &e2f2, &e301
.rx_b_to_forward
    jmp rx_b_forward                                                  ; e2c8: 4c 89 e3    L..

; &e2cb referenced 2 times by &e2b2, &e2bb
.rx_frame_b_dispatch
    sty rx_len                                                        ; e2cb: 8c 28 02    .(.
    cpy #6                                                            ; e2ce: c0 06       ..
    bcc rx_frame_b_bail                                               ; e2d0: 90 eb       ..
    lda rx_src_net                                                    ; e2d2: ad 3f 02    .?.
    bne ce2dd                                                         ; e2d5: d0 06       ..
    lda net_num_b                                                     ; e2d7: ad 00 d0    ...
    sta rx_src_net                                                    ; e2da: 8d 3f 02    .?.
; &e2dd referenced 1 time by &e2d5
.ce2dd
    lda net_num_a                                                     ; e2dd: ad 00 c0    ...
    cmp rx_dst_net                                                    ; e2e0: cd 3d 02    .=.
    bne ce2ea                                                         ; e2e3: d0 05       ..
    lda #0                                                            ; e2e5: a9 00       ..
    sta rx_dst_net                                                    ; e2e7: 8d 3d 02    .=.
; &e2ea referenced 1 time by &e2e3
.ce2ea
    lda rx_dst_stn                                                    ; e2ea: ad 3c 02    .<.
    and rx_dst_net                                                    ; e2ed: 2d 3d 02    -=.
    cmp #&ff                                                          ; e2f0: c9 ff       ..
    bne rx_b_to_forward                                               ; e2f2: d0 d4       ..
    jsr adlc_b_listen                                                 ; e2f4: 20 19 e4     ..
    lda #&c2                                                          ; e2f7: a9 c2       ..
    sta adlc_b_cr1                                                    ; e2f9: 8d 00 d8    ...
    lda rx_port                                                       ; e2fc: ad 41 02    .A.
    cmp #&9c                                                          ; e2ff: c9 9c       ..
    bne rx_b_to_forward                                               ; e301: d0 c5       ..
    lda rx_ctrl                                                       ; e303: ad 40 02    .@.
    cmp #&81                                                          ; e306: c9 81       ..
    beq rx_b_handle_81                                                ; e308: f0 65       .e
    cmp #&80                                                          ; e30a: c9 80       ..
    beq rx_b_handle_80                                                ; e30c: f0 49       .I
    cmp #&82                                                          ; e30e: c9 82       ..
    beq rx_b_handle_82                                                ; e310: f0 0c       ..
    cmp #&83                                                          ; e312: c9 83       ..
    bne rx_b_forward                                                  ; e314: d0 73       .s
; ***************************************************************************************
; Side-B IsNet query (ctrl=&83): targeted network lookup
; 
; Mirror of rx_a_handle_83 (&E195) with A/B swapped: consults
; reachable_via_a (not _b) because the frame arrived on side B.
; Falls through to rx_b_handle_82 when the queried network is
; known.
.rx_b_handle_83
    ldy rx_query_net                                                  ; e316: ac 49 02    .I.
    lda reachable_via_a,y                                             ; e319: b9 5a 03    .Z.
    beq ce354                                                         ; e31c: f0 36       .6
; ***************************************************************************************
; Side-B WhatNet query (ctrl=&82); also IsNet response path
; 
; Mirror of rx_a_handle_82 (&E19D) with A/B swapped throughout:
; stagger seeded from net_num_a, transmit via ADLC B, tx_src_net
; patched to net_num_a, response-data's first payload byte (at
; the tx_ctrl slot) encodes net_num_b. See rx_a_handle_82 for the
; full protocol description.
; &e31e referenced 1 time by &e310
.rx_b_handle_82
    jsr adlc_b_listen                                                 ; e31e: 20 19 e4     ..
    jsr build_query_response                                          ; e321: 20 8d e4     ..
    lda net_num_a                                                     ; e324: ad 00 c0    ...
    sta tx_src_net                                                    ; e327: 8d 5d 04    .].
    sta ctr24_lo                                                      ; e32a: 8d 14 02    ...
    jsr stagger_delay                                                 ; e32d: 20 48 e4     H.
    jsr wait_adlc_b_idle                                              ; e330: 20 90 e6     ..
    jsr transmit_frame_b                                              ; e333: 20 c0 e4     ..
    jsr handshake_rx_b                                                ; e336: 20 ff e5     ..
    jsr build_query_response                                          ; e339: 20 8d e4     ..
    lda net_num_a                                                     ; e33c: ad 00 c0    ...
    sta tx_src_net                                                    ; e33f: 8d 5d 04    .].
    lda net_num_b                                                     ; e342: ad 00 d0    ...
    sta tx_ctrl                                                       ; e345: 8d 5e 04    .^.
    lda rx_query_net                                                  ; e348: ad 49 02    .I.
    sta tx_port                                                       ; e34b: 8d 5f 04    ._.
    jsr transmit_frame_b                                              ; e34e: 20 c0 e4     ..
    jsr handshake_rx_b                                                ; e351: 20 ff e5     ..
; &e354 referenced 1 time by &e31c
.ce354
    jmp main_loop                                                     ; e354: 4c 51 e0    LQ.

; ***************************************************************************************
; Side-B BridgeReset (ctrl=&80): learn topology from scratch
; 
; Mirror of rx_a_handle_80 (&E1D6): wipe reachable_via_* via
; init_reachable_nets, seed the re-announce timer's high byte
; from net_num_a (mirror of A-side seeding from net_num_b), set
; announce_count = 10 and announce_flag = &80 (bit 7 set = next
; outbound on side B). Falls through to rx_b_handle_81.
; &e357 referenced 1 time by &e30c
.rx_b_handle_80
    jsr init_reachable_nets                                           ; e357: 20 24 e4     $.
    lda net_num_a                                                     ; e35a: ad 00 c0    ...
    sta announce_tmr_hi                                               ; e35d: 8d 2b 02    .+.
    lda #0                                                            ; e360: a9 00       ..
    sta announce_tmr_lo                                               ; e362: 8d 2a 02    .*.
    lda #&0a                                                          ; e365: a9 0a       ..
    sta announce_count                                                ; e367: 8d 2c 02    .,.
    lda #&80                                                          ; e36a: a9 80       ..
    sta announce_flag                                                 ; e36c: 8d 29 02    .).
; ***************************************************************************************
; Side-B BridgeReply (ctrl=&81): learn and re-broadcast
; 
; Mirror of rx_a_handle_81 (&E1EE): reads each payload byte from
; offset 6 onward as a network number reachable via side B, marks
; reachable_via_b[x] = &FF for each (mirror of the A-side writing
; reachable_via_a). Appends net_num_b to the payload and falls
; through to rx_b_forward for re-broadcast onto side A.
; &e36f referenced 1 time by &e308
.rx_b_handle_81
    ldy #6                                                            ; e36f: a0 06       ..
; &e371 referenced 1 time by &e37e
.rx_b_learn_loop
    lda rx_dst_stn,y                                                  ; e371: b9 3c 02    .<.
    tax                                                               ; e374: aa          .
    lda #&ff                                                          ; e375: a9 ff       ..
    sta reachable_via_b,x                                             ; e377: 9d 5a 02    .Z.
    iny                                                               ; e37a: c8          .
    cpy rx_len                                                        ; e37b: cc 28 02    .(.
    bne rx_b_learn_loop                                               ; e37e: d0 f1       ..
    lda net_num_b                                                     ; e380: ad 00 d0    ...
    sta rx_dst_stn,y                                                  ; e383: 99 3c 02    .<.
    inc rx_len                                                        ; e386: ee 28 02    .(.
; ***************************************************************************************
; Forward a B-side frame to A, completing the 4-way handshake
; 
; Byte-for-byte mirror of rx_a_forward (&E208) with A and B swapped
; throughout: the inbound scout is pushed via adlc_a_tx, and the
; B-A-B tail bridges the four-way handshake the other direction.
; 
; Reached from rx_b_to_forward (&E2C8), from rx_frame_b's ctrl
; dispatch fall-through (&E314), and from rx_b_handle_81's
; fall-through at &E387.
; 
; See rx_a_forward for the full per-stage explanation.
; &e389 referenced 2 times by &e2c8, &e314
.rx_b_forward
    lda rx_len                                                        ; e389: ad 28 02    .(.
    tax                                                               ; e38c: aa          .
    and #&fe                                                          ; e38d: 29 fe       ).
    sta rx_len                                                        ; e38f: 8d 28 02    .(.
    jsr wait_adlc_a_idle                                              ; e392: 20 dc e6     ..
    ldy #0                                                            ; e395: a0 00       ..
; &e397 referenced 1 time by &e3b0
.rx_b_forward_pair_loop
    jsr wait_adlc_a_irq                                               ; e397: 20 e4 e3     ..
    bit adlc_a_cr1                                                    ; e39a: 2c 00 c8    ,..
    bvc rx_b_forward_done                                             ; e39d: 50 42       PB
    lda rx_dst_stn,y                                                  ; e39f: b9 3c 02    .<.
    sta adlc_a_tx                                                     ; e3a2: 8d 02 c8    ...
    iny                                                               ; e3a5: c8          .
    lda rx_dst_stn,y                                                  ; e3a6: b9 3c 02    .<.
    sta adlc_a_tx                                                     ; e3a9: 8d 02 c8    ...
    iny                                                               ; e3ac: c8          .
    cpy rx_len                                                        ; e3ad: cc 28 02    .(.
    bcc rx_b_forward_pair_loop                                        ; e3b0: 90 e5       ..
    txa                                                               ; e3b2: 8a          .
    ror a                                                             ; e3b3: 6a          j
    bcc rx_b_forward_ack_round                                        ; e3b4: 90 09       ..
    jsr wait_adlc_a_irq                                               ; e3b6: 20 e4 e3     ..
    lda rx_dst_stn,y                                                  ; e3b9: b9 3c 02    .<.
    sta adlc_a_tx                                                     ; e3bc: 8d 02 c8    ...
; &e3bf referenced 1 time by &e3b4
.rx_b_forward_ack_round
    lda #&3f ; '?'                                                    ; e3bf: a9 3f       .?
    sta adlc_a_cr2                                                    ; e3c1: 8d 01 c8    ...
    jsr wait_adlc_a_irq                                               ; e3c4: 20 e4 e3     ..
    lda #&5a ; 'Z'                                                    ; e3c7: a9 5a       .Z
    sta mem_ptr_lo                                                    ; e3c9: 85 80       ..
    lda #4                                                            ; e3cb: a9 04       ..
    sta mem_ptr_hi                                                    ; e3cd: 85 81       ..
    jsr handshake_rx_a                                                ; e3cf: 20 6e e5     n.
    jsr transmit_frame_b                                              ; e3d2: 20 c0 e4     ..
    jsr handshake_rx_b                                                ; e3d5: 20 ff e5     ..
    jsr transmit_frame_a                                              ; e3d8: 20 17 e5     ..
    jsr handshake_rx_a                                                ; e3db: 20 6e e5     n.
    jsr transmit_frame_b                                              ; e3de: 20 c0 e4     ..
; &e3e1 referenced 1 time by &e39d
.rx_b_forward_done
    jmp main_loop                                                     ; e3e1: 4c 51 e0    LQ.

; ***************************************************************************************
; Wait for ADLC A IRQ (polled)
; 
; Spin reading SR1 of ADLC A until the IRQ bit (bit 7) is set. Called
; from 19 sites where the code needs to wait for the ADLC to signal an
; event (frame complete, RX data available, TX ready, etc.).
; 
; The Bridge does not route the ADLC ~IRQ output to the 6502 ~IRQ line
; (that pin is used for the self-test push-button), so ADLC attention
; is obtained by polling.
; &e3e4 referenced 19 times by &e0ef, &e106, &e397, &e3b6, &e3c4, &e3e7, &e523, &e550, &e562, &e575, &e583, &e593, &f125, &f15c, &f1da, &f1ea, &f20d, &f22a, &f242
.wait_adlc_a_irq
    bit adlc_a_cr1                                                    ; e3e4: 2c 00 c8    ,..
    bpl wait_adlc_a_irq                                               ; e3e7: 10 fb       ..
    rts                                                               ; e3e9: 60          `

; ***************************************************************************************
; Wait for ADLC B IRQ (polled)
; 
; As wait_adlc_a_irq but for ADLC B.
; &e3ea referenced 19 times by &e216, &e235, &e243, &e270, &e287, &e3ed, &e4cc, &e4f9, &e50b, &e606, &e614, &e624, &f139, &f149, &f16c, &f189, &f1a1, &f1c6, &f1fd
.wait_adlc_b_irq
    bit adlc_b_cr1                                                    ; e3ea: 2c 00 d8    ,..
    bpl wait_adlc_b_irq                                               ; e3ed: 10 fb       ..
    rts                                                               ; e3ef: 60          `

; ***************************************************************************************
; ADLC A full reset, then enter RX listen
; 
; Aborts all ADLC A activity and returns it to idle RX listen mode.
; Falls through to adlc_a_listen. Called from the reset handler.
; CR1=&C1: reset TX+RX, AC=1 (enable CR3/CR4 access)
; &e3f0 referenced 1 time by &e005
.adlc_a_full_reset
    lda #&c1                                                          ; e3f0: a9 c1       ..
    sta adlc_a_cr1                                                    ; e3f2: 8d 00 c8    ...
; CR4=&1E: 8-bit RX, abort extend, NRZ
    lda #&1e                                                          ; e3f5: a9 1e       ..
    sta adlc_a_tx2                                                    ; e3f7: 8d 03 c8    ...
; CR3=&00: normal, NRZ, no loop-back, no DTR
    lda #0                                                            ; e3fa: a9 00       ..
    sta adlc_a_cr2                                                    ; e3fc: 8d 01 c8    ...
; ***************************************************************************************
; Enter ADLC A RX listen mode
; 
; TX held in reset, RX active. IRQs are generated internally by the
; chip but the ~IRQ output is not wired; see wait_adlc_a_irq.
; CR1=&82: TX in reset, RX interrupts enabled
; &e3ff referenced 2 times by &e173, &e19d
.adlc_a_listen
    lda #&82                                                          ; e3ff: a9 82       ..
    sta adlc_a_cr1                                                    ; e401: 8d 00 c8    ...
; CR2=&67: clear status, FC_TDRA, 2/1-byte, PSE
    lda #&67 ; 'g'                                                    ; e404: a9 67       .g
    sta adlc_a_cr2                                                    ; e406: 8d 01 c8    ...
    rts                                                               ; e409: 60          `

; ***************************************************************************************
; ADLC B full reset, then enter RX listen
; 
; Byte-for-byte mirror of adlc_a_full_reset, targeting ADLC B's
; register set at &D800-&D803. Falls through to adlc_b_listen.
; CR1=&C1: reset TX+RX, AC=1 (enable CR3/CR4 access)
; &e40a referenced 1 time by &e008
.adlc_b_full_reset
    lda #&c1                                                          ; e40a: a9 c1       ..
    sta adlc_b_cr1                                                    ; e40c: 8d 00 d8    ...
; CR4=&1E: 8-bit RX, abort extend, NRZ
    lda #&1e                                                          ; e40f: a9 1e       ..
    sta adlc_b_tx2                                                    ; e411: 8d 03 d8    ...
; CR3=&00: bit 7=0 -> LOC/DTR pin HIGH -> status LED OFF
    lda #0                                                            ; e414: a9 00       ..
    sta adlc_b_cr2                                                    ; e416: 8d 01 d8    ...
; ***************************************************************************************
; Enter ADLC B RX listen mode
; 
; Mirror of adlc_a_listen for ADLC B.
; CR1=&82: TX in reset, RX interrupts enabled
; &e419 referenced 2 times by &e2f4, &e31e
.adlc_b_listen
    lda #&82                                                          ; e419: a9 82       ..
    sta adlc_b_cr1                                                    ; e41b: 8d 00 d8    ...
; CR2=&67: clear status, FC_TDRA, 2/1-byte, PSE
    lda #&67 ; 'g'                                                    ; e41e: a9 67       .g
    sta adlc_b_cr2                                                    ; e420: 8d 01 d8    ...
    rts                                                               ; e423: 60          `

; ***************************************************************************************
; Clear the per-port station maps and mark bridge/broadcast
; 
; Zeroes reachable_via_b and reachable_via_a (256 bytes each), then writes &FF
; to three slots:
; 
;   reachable_via_a[net_num_a]    — the bridge's port-A station
;   reachable_via_b[net_num_b]    — the bridge's port-B station
;   reachable_via_b[255]             — broadcast slot
;   reachable_via_a[255]             — broadcast slot
; 
; Called from the reset handler and also re-invoked at &E1D6 and
; &E357 — probably after network topology changes or administrative
; re-init. The &FF-marked slots prevent the bridge from being
; confused by traffic to/from its own station IDs or broadcasts
; during routing decisions.
; Y = 0, A = 0: set up to clear both tables
; &e424 referenced 3 times by &e002, &e1d6, &e357
.init_reachable_nets
    ldy #0                                                            ; e424: a0 00       ..
    lda #0                                                            ; e426: a9 00       ..
; Zero reachable_via_b[Y]
; &e428 referenced 1 time by &e42f
.loop_ce428
    sta reachable_via_b,y                                             ; e428: 99 5a 02    .Z.
; Zero reachable_via_a[Y]
    sta reachable_via_a,y                                             ; e42b: 99 5a 03    .Z.
    iny                                                               ; e42e: c8          .
; Loop over all 256 slots (Y wraps back to 0)
    bne loop_ce428                                                    ; e42f: d0 f7       ..
; Marker value &FF for the special slots below
    lda #&ff                                                          ; e431: a9 ff       ..
; Port A bridge-station slot -> mark in reachable_via_a
    ldy net_num_a                                                     ; e433: ac 00 c0    ...
    sta reachable_via_a,y                                             ; e436: 99 5a 03    .Z.
; Port B bridge-station slot -> mark in reachable_via_b
    ldy net_num_b                                                     ; e439: ac 00 d0    ...
    sta reachable_via_b,y                                             ; e43c: 99 5a 02    .Z.
; Broadcast slot (255) in both maps
    ldy #&ff                                                          ; e43f: a0 ff       ..
    sta reachable_via_b,y                                             ; e441: 99 5a 02    .Z.
    sta reachable_via_a,y                                             ; e444: 99 5a 03    .Z.
    rts                                                               ; e447: 60          `

; ***************************************************************************************
; Fixed prelude + per-count delay scaled by ctr24_lo
; 
; A calibrated busy-wait used by the query-response paths to stagger
; their transmissions. Called from rx_a_handle_82 (&E1AC) and
; rx_b_handle_82 (&E32D), in each case with ctr24_lo pre-loaded
; with the bridge's opposite-side network number (net_num_b for
; A-side responses, net_num_a for B-side responses).
; 
; Two phases:
; 
;   Prelude (~&40 * (dey/bne) cycles): a fixed settling delay,
;   the same regardless of caller. Roughly &40 * 5 = 320 cycles
;   = ~160 us at 2 MHz.
; 
;   Per-count loop (ctr24_lo iterations * (&14 * (dey/bne) + dec/bne)
;   cycles): roughly ctr24_lo * 110 cycles. For a typical network
;   number of ~24, that's ~2600 cycles = ~1.3 ms.
; 
; For the range of network numbers permitted (1-127), the total
; delay runs from ~215 us to ~7 ms. This spread means multiple
; bridges on the same segment responding to a broadcast query
; (ctrl=&82) transmit their responses at measurably different
; times, reducing the chance of collisions on the shared medium.
; Bridges with higher network numbers back off longer -- a cheap
; deterministic priority scheme that requires no coordination.
; Y = &40: fixed prelude count
; &e448 referenced 2 times by &e1ac, &e32d
.stagger_delay
    ldy #&40 ; '@'                                                    ; e448: a0 40       .@
; Tight dey/bne prelude (~160 us)
; &e44a referenced 1 time by &e44b
.loop_ce44a
    dey                                                               ; e44a: 88          .
    bne loop_ce44a                                                    ; e44b: d0 fd       ..
; Y = &14: per-iteration inner count
; &e44d referenced 1 time by &e455
.loop_ce44d
    ldy #&14                                                          ; e44d: a0 14       ..
; Tight dey/bne inner loop (~50 us)
; &e44f referenced 1 time by &e450
.loop_ce44f
    dey                                                               ; e44f: 88          .
    bne loop_ce44f                                                    ; e450: d0 fd       ..
; Decrement outer counter
    dec ctr24_lo                                                      ; e452: ce 14 02    ...
; Loop for ctr24_lo iterations total
    bne loop_ce44d                                                    ; e455: d0 f6       ..
    rts                                                               ; e457: 60          `

; ***************************************************************************************
; Populate outbound frame with a side-B bridge announcement
; 
; Populates the outbound frame control block at &045A-&0460 with
; an all-broadcast bridge announcement carrying the B-side network
; number as its payload. At reset time this is transmitted via
; ADLC A first (announcing "network N is reachable through me" to
; side A's stations), then tx_data0 is patched to net_num_a and it
; is re-transmitted via ADLC B.
; 
;   tx_dst_stn = &FF                    broadcast station
;   tx_dst_net = &FF                    broadcast network
;   tx_src_stn = &18                    firmware marker (see below)
;   tx_src_net = &18                    firmware marker (see below)
;   tx_ctrl    = &80                    initial-announcement ctrl
;   tx_port    = &9C                    bridge-protocol port
;   tx_data0   = net_num_b              network number on side B
; 
; The src_stn/src_net fields are both set to the constant &18. The
; Bridge has no station number of its own (only network numbers,
; per the Installation Guide) so these fields are not real addresses.
; Receivers do not use them for routing -- rx_a_handle_81 reads the
; payload starting at offset 6 and ignores bytes 2-3 entirely. The
; most plausible role for &18 is defensive redundancy: together with
; dst=(&FF,&FF), ctrl=&80/&81 and port=&9C it gives a receiver
; multiple ways to confirm that a received frame is a well-formed
; bridge announcement.
; 
; Also writes &06 to tx_end_lo and &04 to tx_end_hi (so the transmit
; routine sends bytes &045A..&0460 inclusive = 7 bytes when X=1),
; loads X=1 (trailing-byte flag for transmit_frame_a), and points
; mem_ptr at the frame block (&045A).
; 
; Called from the reset handler at &E038 and again from &E098 (the
; main-loop periodic re-announce path). A structurally identical
; cousin builder lives at sub_ce48d (&E48D) and is called from four
; sites; it populates the same fields with values drawn from RAM
; variables at rx_src_stn and rx_query_net rather than baked-in
; constants.
; dst = &FFFF: broadcast station + network
; &e458 referenced 2 times by &e038, &e098
.build_announce_b
    lda #&ff                                                          ; e458: a9 ff       ..
    sta tx_dst_stn                                                    ; e45a: 8d 5a 04    .Z.
    sta tx_dst_net                                                    ; e45d: 8d 5b 04    .[.
; src = &1818: firmware marker (Bridge has no station)
    lda #&18                                                          ; e460: a9 18       ..
    sta tx_src_stn                                                    ; e462: 8d 5c 04    .\.
    sta tx_src_net                                                    ; e465: 8d 5d 04    .].
; port = &9C (bridge-protocol port)
    lda #&9c                                                          ; e468: a9 9c       ..
    sta tx_port                                                       ; e46a: 8d 5f 04    ._.
; ctrl = &80 (scout)
    lda #&80                                                          ; e46d: a9 80       ..
    sta tx_ctrl                                                       ; e46f: 8d 5e 04    .^.
; Payload byte 0: bridge's network number on side B
    lda net_num_b                                                     ; e472: ad 00 d0    ...
    sta tx_data0                                                      ; e475: 8d 60 04    .`.
; X = 1: probable side selector (B)
    ldx #1                                                            ; e478: a2 01       ..
; tx command block: len=&06, ?=&04 (provisional)
    lda #6                                                            ; e47a: a9 06       ..
    sta tx_end_lo                                                     ; e47c: 8d 00 02    ...
    lda #4                                                            ; e47f: a9 04       ..
    sta tx_end_hi                                                     ; e481: 8d 01 02    ...
; mem_ptr = &045A (start of frame block)
    lda #&5a ; 'Z'                                                    ; e484: a9 5a       .Z
    sta mem_ptr_lo                                                    ; e486: 85 80       ..
    lda #4                                                            ; e488: a9 04       ..
    sta mem_ptr_hi                                                    ; e48a: 85 81       ..
    rts                                                               ; e48c: 60          `

; ***************************************************************************************
; Build a reply-scout frame addressed back to the querier
; 
; A second frame-builder (sibling of build_announce_b) used by the
; bridge-query response path. Where build_announce_b writes a
; broadcast-addressed template, this one builds a unicast reply:
; 
;   tx_dst_stn = rx_src_stn          station that sent the query
;   tx_dst_net = 0                   local network
;   tx_src_stn = 0                   Bridge has no station
;   tx_src_net = 0                   (caller patches to net_num_?)
;   tx_ctrl    = &80                 scout control byte
;   tx_port    = rx_query_port       response port from byte 12 of query
;   X          = 0                   no trailing payload
; 
; Also writes tx_end_lo=&06 / tx_end_hi=&04 and points mem_ptr at
; &045A so a subsequent transmit_frame_? sends the 6-byte scout.
; 
; Called from the two query-response paths (&E1A0 and &E1B8 on
; side A; &E321 and &E339 on side B). Each caller then patches a
; subset of the fields before calling transmit_frame_? -- the
; idiomatic second call in particular overwrites tx_ctrl and
; tx_port to carry the bridge's routing answer.
; dst_stn = rx_src_stn: reply to the querier
; &e48d referenced 4 times by &e1a0, &e1b8, &e321, &e339
.build_query_response
    lda rx_src_stn                                                    ; e48d: ad 3e 02    .>.
    sta tx_dst_stn                                                    ; e490: 8d 5a 04    .Z.
; dst_net = 0: reply on local network
    lda #0                                                            ; e493: a9 00       ..
    sta tx_dst_net                                                    ; e495: 8d 5b 04    .[.
; src = (0, 0): Bridge has no station
    lda #0                                                            ; e498: a9 00       ..
    sta tx_src_stn                                                    ; e49a: 8d 5c 04    .\.
    sta tx_src_net                                                    ; e49d: 8d 5d 04    .].
; ctrl = &80: scout
    lda #&80                                                          ; e4a0: a9 80       ..
    sta tx_ctrl                                                       ; e4a2: 8d 5e 04    .^.
; port = rx_query_port: from byte 12 of query
    lda rx_query_port                                                 ; e4a5: ad 48 02    .H.
    sta tx_port                                                       ; e4a8: 8d 5f 04    ._.
; X = 0: no trailing payload byte
    ldx #0                                                            ; e4ab: a2 00       ..
; tx_end = &0406: 6-byte scout
    lda #6                                                            ; e4ad: a9 06       ..
    sta tx_end_lo                                                     ; e4af: 8d 00 02    ...
    lda #4                                                            ; e4b2: a9 04       ..
    sta tx_end_hi                                                     ; e4b4: 8d 01 02    ...
; mem_ptr = &045A: frame-block base
    lda #&5a ; 'Z'                                                    ; e4b7: a9 5a       .Z
    sta mem_ptr_lo                                                    ; e4b9: 85 80       ..
    lda #4                                                            ; e4bb: a9 04       ..
    sta mem_ptr_hi                                                    ; e4bd: 85 81       ..
    rts                                                               ; e4bf: 60          `

; ***************************************************************************************
; Send the frame at mem_ptr out through ADLC B's TX FIFO
; 
; Byte-for-byte mirror of transmit_frame_a (&E517) with adlc_a_*
; replaced by adlc_b_*. Everything there applies here — same entry
; conditions, same end-pointer semantics (tx_end_lo/hi), same X=0/1
; trailing-byte flag, same escape-to-main-loop on unexpected SR1
; state, same normal exit that resets mem_ptr to &045A.
; 
; Called from seven sites: reset (&E04E), &E0D8, &E257, &E333, &E34E,
; &E3D2, &E3DE.
; &e4c0 referenced 7 times by &e04e, &e0d8, &e257, &e333, &e34e, &e3d2, &e3de
.transmit_frame_b
    lda #&e7                                                          ; e4c0: a9 e7       ..
    sta adlc_b_cr2                                                    ; e4c2: 8d 01 d8    ...
    lda #&44 ; 'D'                                                    ; e4c5: a9 44       .D
    sta adlc_b_cr1                                                    ; e4c7: 8d 00 d8    ...
    ldy #0                                                            ; e4ca: a0 00       ..
; &e4cc referenced 2 times by &e4ec, &e4f3
.ce4cc
    jsr wait_adlc_b_irq                                               ; e4cc: 20 ea e3     ..
    bit adlc_b_cr1                                                    ; e4cf: 2c 00 d8    ,..
    bvs ce4d9                                                         ; e4d2: 70 05       p.
; &e4d4 referenced 1 time by &e4ff
.ce4d4
    pla                                                               ; e4d4: 68          h
    pla                                                               ; e4d5: 68          h
    jmp main_loop                                                     ; e4d6: 4c 51 e0    LQ.

; &e4d9 referenced 1 time by &e4d2
.ce4d9
    lda (mem_ptr_lo),y                                                ; e4d9: b1 80       ..
    sta adlc_b_tx                                                     ; e4db: 8d 02 d8    ...
    iny                                                               ; e4de: c8          .
    lda (mem_ptr_lo),y                                                ; e4df: b1 80       ..
    sta adlc_b_tx                                                     ; e4e1: 8d 02 d8    ...
    iny                                                               ; e4e4: c8          .
    bne ce4e9                                                         ; e4e5: d0 02       ..
    inc mem_ptr_hi                                                    ; e4e7: e6 81       ..
; &e4e9 referenced 1 time by &e4e5
.ce4e9
    cpy tx_end_lo                                                     ; e4e9: cc 00 02    ...
    bne ce4cc                                                         ; e4ec: d0 de       ..
    lda mem_ptr_hi                                                    ; e4ee: a5 81       ..
    cmp tx_end_hi                                                     ; e4f0: cd 01 02    ...
    bcc ce4cc                                                         ; e4f3: 90 d7       ..
    txa                                                               ; e4f5: 8a          .
    ror a                                                             ; e4f6: 6a          j
    bcc ce506                                                         ; e4f7: 90 0d       ..
    jsr wait_adlc_b_irq                                               ; e4f9: 20 ea e3     ..
    bit adlc_b_cr1                                                    ; e4fc: 2c 00 d8    ,..
    bvc ce4d4                                                         ; e4ff: 50 d3       P.
    lda (mem_ptr_lo),y                                                ; e501: b1 80       ..
    sta adlc_b_tx                                                     ; e503: 8d 02 d8    ...
; &e506 referenced 1 time by &e4f7
.ce506
    lda #&3f ; '?'                                                    ; e506: a9 3f       .?
    sta adlc_b_cr2                                                    ; e508: 8d 01 d8    ...
    jsr wait_adlc_b_irq                                               ; e50b: 20 ea e3     ..
    lda #&5a ; 'Z'                                                    ; e50e: a9 5a       .Z
    sta mem_ptr_lo                                                    ; e510: 85 80       ..
    lda #4                                                            ; e512: a9 04       ..
    sta mem_ptr_hi                                                    ; e514: 85 81       ..
    rts                                                               ; e516: 60          `

; ***************************************************************************************
; Send the frame at mem_ptr out through ADLC A's TX FIFO
; 
; Sends the frame starting at mem_ptr (&80/&81 — normally pointing at
; the outbound control block &045A) through ADLC A's TX FIFO. Termi-
; nation is controlled by the 16-bit pointer tx_end_lo/tx_end_hi
; (&0200/&0201): the loop sends byte pairs until mem_ptr + Y reaches
; or passes (tx_end_hi:tx_end_lo). X is a flag — non-zero means send
; one extra trailing byte after the terminator (used by builders that
; append a payload like build_announce_b's net_num_b at &0460).
; 
; On entry:
;   mem_ptr_lo/hi                      start address of frame
;   tx_end_lo/hi                       end address (exclusive pair)
;   X                                  0 = no trailing byte,
;                                      1 = send one trailing byte
;   ADLC A must already be primed by a frame builder
; 
; On exit (normal RTS):
;   mem_ptr_lo/hi reset to &045A       ready for next builder
;   ADLC A's TX FIFO flushed, CR2 = &3F
; 
; Abnormal exit: if any of the three wait_adlc_a_irq polls returns
; with SR1's V-bit clear instead of set (meaning the ADLC didn't reach
; the expected TDRA state), the routine drops the caller's return
; address from the stack and JMP's into the main loop at &E051 —
; the same escape-to-main pattern used by wait_adlc_a_idle.
; 
; Called from seven sites: reset (&E03E), &E0AD, &E1B2, &E1CD, &E251,
; &E25D, &E3D8.
; CR2 = &E7: prime for TX (FC_TDRA, 2-byte, PSE+extras)
; &e517 referenced 7 times by &e03e, &e0ad, &e1b2, &e1cd, &e251, &e25d, &e3d8
.transmit_frame_a
    lda #&e7                                                          ; e517: a9 e7       ..
    sta adlc_a_cr2                                                    ; e519: 8d 01 c8    ...
; CR1 = &44: arm TX interrupts
    lda #&44 ; 'D'                                                    ; e51c: a9 44       .D
    sta adlc_a_cr1                                                    ; e51e: 8d 00 c8    ...
; Y = 0 (buffer offset into frame)
    ldy #0                                                            ; e521: a0 00       ..
; Wait for ADLC A to flag TDRA
; &e523 referenced 2 times by &e543, &e54a
.ce523
    jsr wait_adlc_a_irq                                               ; e523: 20 e4 e3     ..
; Test SR1 V-flag (TDRA bit 6)
    bit adlc_a_cr1                                                    ; e526: 2c 00 c8    ,..
; V set -> room in FIFO, send next pair
    bvs ce530                                                         ; e529: 70 05       p.
; V clear: abandon frame and escape to main loop
; &e52b referenced 1 time by &e556
.ce52b
    pla                                                               ; e52b: 68          h
    pla                                                               ; e52c: 68          h
    jmp main_loop                                                     ; e52d: 4c 51 e0    LQ.

; Load and send frame byte Y
; &e530 referenced 1 time by &e529
.ce530
    lda (mem_ptr_lo),y                                                ; e530: b1 80       ..
    sta adlc_a_tx                                                     ; e532: 8d 02 c8    ...
    iny                                                               ; e535: c8          .
; Load and send frame byte Y+1
    lda (mem_ptr_lo),y                                                ; e536: b1 80       ..
    sta adlc_a_tx                                                     ; e538: 8d 02 c8    ...
    iny                                                               ; e53b: c8          .
; Y wrapped: bump mem_ptr_hi
    bne ce540                                                         ; e53c: d0 02       ..
    inc mem_ptr_hi                                                    ; e53e: e6 81       ..
; Terminate once Y == tx_end_lo and hi == tx_end_hi
; &e540 referenced 1 time by &e53c
.ce540
    cpy tx_end_lo                                                     ; e540: cc 00 02    ...
    bne ce523                                                         ; e543: d0 de       ..
    lda mem_ptr_hi                                                    ; e545: a5 81       ..
    cmp tx_end_hi                                                     ; e547: cd 01 02    ...
    bcc ce523                                                         ; e54a: 90 d7       ..
; X!=0: send one more trailing byte (X bit 0 only)
    txa                                                               ; e54c: 8a          .
    ror a                                                             ; e54d: 6a          j
    bcc ce55d                                                         ; e54e: 90 0d       ..
; Wait for TDRA before trailing byte
    jsr wait_adlc_a_irq                                               ; e550: 20 e4 e3     ..
    bit adlc_a_cr1                                                    ; e553: 2c 00 c8    ,..
; V clear -> escape (mirror of &E52B)
    bvc ce52b                                                         ; e556: 50 d3       P.
; Send trailing byte (tx_data0 in announce frames)
    lda (mem_ptr_lo),y                                                ; e558: b1 80       ..
    sta adlc_a_tx                                                     ; e55a: 8d 02 c8    ...
; CR2 = &3F: signal end of burst, wait for completion
; &e55d referenced 1 time by &e54e
.ce55d
    lda #&3f ; '?'                                                    ; e55d: a9 3f       .?
    sta adlc_a_cr2                                                    ; e55f: 8d 01 c8    ...
    jsr wait_adlc_a_irq                                               ; e562: 20 e4 e3     ..
; Reset mem_ptr to &045A for next builder
    lda #&5a ; 'Z'                                                    ; e565: a9 5a       .Z
    sta mem_ptr_lo                                                    ; e567: 85 80       ..
    lda #4                                                            ; e569: a9 04       ..
    sta mem_ptr_hi                                                    ; e56b: 85 81       ..
    rts                                                               ; e56d: 60          `

; ***************************************************************************************
; Receive a handshake frame on ADLC A and stage it for forward
; 
; The receive half of four-way-handshake bridging for the A side.
; Enables RX on ADLC A, drains an inbound frame byte-by-byte into
; the outbound buffer starting at tx_dst_stn (&045A), then sets up
; tx_end_lo/hi so the next call to transmit_frame_b transmits the
; just-received frame out of the other port verbatim.
; 
; The drain is capped at `top_ram_page` (set by the boot RAM test)
; so very long frames fill available RAM and no further.
; 
; After the drain, does three pieces of address fix-up on the
; now-staged frame:
; 
;   * If tx_src_net (byte 3 of the frame) is zero, fill it with
;     net_num_a. Many Econet senders leave src_net as zero to mean
;     "my local network"; the Bridge makes that explicit before
;     forwarding.
; 
;   * Reject the frame if tx_dst_net is zero (no destination
;     network declared) or if reachable_via_b has no entry for
;     that network (we don't know a route).
; 
;   * If tx_dst_net equals net_num_b (our own B-side network),
;     normalise it to zero -- from side B's perspective the frame
;     is now "local".
; 
; On any of the "reject" paths above, and on any sub-step that
; fails (no AP/RDA, no Frame Valid, no response at all), takes
; the standard escape-to-main-loop exit: PLA/PLA/JMP main_loop.
; 
; On success, return to the caller with mem_ptr / tx_end_lo / tx_end_hi
; ready for transmit_frame_b (or transmit_frame_a in the reverse
; direction for queries). Mirror of handshake_rx_b (&E5FF).
; 
; Called from five sites: &E1B5 and &E1D0 (rx_a_handle_82/83 query
; paths), &E254 and &E3DB (forward tails), and &E3CF (also a forward
; tail).
; CR1 = &82: TX in reset, RX IRQs enabled
; &e56e referenced 5 times by &e1b5, &e1d0, &e254, &e3cf, &e3db
.handshake_rx_a
    lda #&82                                                          ; e56e: a9 82       ..
    sta adlc_a_cr1                                                    ; e570: 8d 00 c8    ...
; A = &01: mask SR2 bit 0 (AP)
    lda #1                                                            ; e573: a9 01       ..
; Wait for the first RX event
    jsr wait_adlc_a_irq                                               ; e575: 20 e4 e3     ..
    bit adlc_a_cr2                                                    ; e578: 2c 01 c8    ,..
; No AP: nothing arrived, escape to main
    beq ce5b1                                                         ; e57b: f0 34       .4
; Read byte 0: destination station
    lda adlc_a_tx                                                     ; e57d: ad 02 c8    ...
    sta tx_dst_stn                                                    ; e580: 8d 5a 04    .Z.
    jsr wait_adlc_a_irq                                               ; e583: 20 e4 e3     ..
    bit adlc_a_cr2                                                    ; e586: 2c 01 c8    ,..
; Second IRQ gone -> frame truncated, escape
    bpl ce5b1                                                         ; e589: 10 26       .&
; Read byte 1: destination network
    lda adlc_a_tx                                                     ; e58b: ad 02 c8    ...
    sta tx_dst_net                                                    ; e58e: 8d 5b 04    .[.
; Y = 2: continue draining pairs into (&045A)+Y
    ldy #2                                                            ; e591: a0 02       ..
; &e593 referenced 2 times by &e5a7, &e5af
.ce593
    jsr wait_adlc_a_irq                                               ; e593: 20 e4 e3     ..
    bit adlc_a_cr2                                                    ; e596: 2c 01 c8    ,..
; End-of-frame detected mid-pair
    bpl ce5b6                                                         ; e599: 10 1b       ..
    lda adlc_a_tx                                                     ; e59b: ad 02 c8    ...
    sta (mem_ptr_lo),y                                                ; e59e: 91 80       ..
    iny                                                               ; e5a0: c8          .
    lda adlc_a_tx                                                     ; e5a1: ad 02 c8    ...
    sta (mem_ptr_lo),y                                                ; e5a4: 91 80       ..
    iny                                                               ; e5a6: c8          .
    bne ce593                                                         ; e5a7: d0 ea       ..
; Advance to next page of the staging buffer
    inc mem_ptr_hi                                                    ; e5a9: e6 81       ..
    lda mem_ptr_hi                                                    ; e5ab: a5 81       ..
; Stop if we would overrun available RAM
    cmp top_ram_page                                                  ; e5ad: c5 82       ..
    bcc ce593                                                         ; e5af: 90 e2       ..
; Escape to main (PLA/PLA/JMP pattern)
; &e5b1 referenced 5 times by &e57b, &e589, &e5c5, &e5e4, &e5e9
.ce5b1
    pla                                                               ; e5b1: 68          h
    pla                                                               ; e5b2: 68          h
    jmp main_loop                                                     ; e5b3: 4c 51 e0    LQ.

; CR1=0, CR2=&84: halt chip post-drain
; &e5b6 referenced 1 time by &e599
.ce5b6
    lda #0                                                            ; e5b6: a9 00       ..
    sta adlc_a_cr1                                                    ; e5b8: 8d 00 c8    ...
    lda #&84                                                          ; e5bb: a9 84       ..
    sta adlc_a_cr2                                                    ; e5bd: 8d 01 c8    ...
    lda #2                                                            ; e5c0: a9 02       ..
    bit adlc_a_cr2                                                    ; e5c2: 2c 01 c8    ,..
; No Frame Valid -> corrupt/short, escape
    beq ce5b1                                                         ; e5c5: f0 ea       ..
; FV set but no RDA -> drained, proceed
    bpl ce5cf                                                         ; e5c7: 10 06       ..
; One trailing byte remained
    lda adlc_a_tx                                                     ; e5c9: ad 02 c8    ...
    sta (mem_ptr_lo),y                                                ; e5cc: 91 80       ..
    iny                                                               ; e5ce: c8          .
; Finalise tx_end_lo = byte count (rounded even)
; &e5cf referenced 1 time by &e5c7
.ce5cf
    tya                                                               ; e5cf: 98          .
    tax                                                               ; e5d0: aa          .
    and #&fe                                                          ; e5d1: 29 fe       ).
    sta tx_end_lo                                                     ; e5d3: 8d 00 02    ...
; If src_net was zero, normalise to net_num_a
    lda tx_src_net                                                    ; e5d6: ad 5d 04    .].
    bne ce5e1                                                         ; e5d9: d0 06       ..
    lda net_num_a                                                     ; e5db: ad 00 c0    ...
    sta tx_src_net                                                    ; e5de: 8d 5d 04    .].
; Forwardability check on tx_dst_net
; &e5e1 referenced 1 time by &e5d9
.ce5e1
    ldy tx_dst_net                                                    ; e5e1: ac 5b 04    .[.
; dst_net = 0 -> reject
    beq ce5b1                                                         ; e5e4: f0 cb       ..
; Not reachable via side B -> reject
    lda reachable_via_b,y                                             ; e5e6: b9 5a 02    .Z.
    beq ce5b1                                                         ; e5e9: f0 c6       ..
; dst_net = net_num_b -> frame is local on B
    cpy net_num_b                                                     ; e5eb: cc 00 d0    ...
    bne ce5f5                                                         ; e5ee: d0 05       ..
; ...normalise to 0 for the outbound frame
    lda #0                                                            ; e5f0: a9 00       ..
    sta tx_dst_net                                                    ; e5f2: 8d 5b 04    .[.
; tx_end_hi = final mem_ptr_hi (multi-page)
; &e5f5 referenced 1 time by &e5ee
.ce5f5
    lda mem_ptr_hi                                                    ; e5f5: a5 81       ..
    sta tx_end_hi                                                     ; e5f7: 8d 01 02    ...
; Reset mem_ptr_hi so transmit reads from &045A
    lda #4                                                            ; e5fa: a9 04       ..
    sta mem_ptr_hi                                                    ; e5fc: 85 81       ..
    rts                                                               ; e5fe: 60          `

; ***************************************************************************************
; Receive a handshake frame on ADLC B and stage it for forward
; 
; Byte-for-byte mirror of handshake_rx_a (&E56E) with adlc_a_*
; replaced by adlc_b_* and the A/B network-number swaps in the
; address normalisation: src_net defaults to net_num_b, and the
; forwardability check is against reachable_via_a.
; 
; Called from five sites: &E24E, &E25A, &E336, &E351, &E3D5.
; See handshake_rx_a for the per-instruction explanation.
; &e5ff referenced 5 times by &e24e, &e25a, &e336, &e351, &e3d5
.handshake_rx_b
    lda #&82                                                          ; e5ff: a9 82       ..
    sta adlc_b_cr1                                                    ; e601: 8d 00 d8    ...
    lda #1                                                            ; e604: a9 01       ..
    jsr wait_adlc_b_irq                                               ; e606: 20 ea e3     ..
    bit adlc_b_cr2                                                    ; e609: 2c 01 d8    ,..
    beq ce642                                                         ; e60c: f0 34       .4
    lda adlc_b_tx                                                     ; e60e: ad 02 d8    ...
    sta tx_dst_stn                                                    ; e611: 8d 5a 04    .Z.
    jsr wait_adlc_b_irq                                               ; e614: 20 ea e3     ..
    bit adlc_b_cr2                                                    ; e617: 2c 01 d8    ,..
    bpl ce642                                                         ; e61a: 10 26       .&
    lda adlc_b_tx                                                     ; e61c: ad 02 d8    ...
    sta tx_dst_net                                                    ; e61f: 8d 5b 04    .[.
    ldy #2                                                            ; e622: a0 02       ..
; &e624 referenced 2 times by &e638, &e640
.ce624
    jsr wait_adlc_b_irq                                               ; e624: 20 ea e3     ..
    bit adlc_b_cr2                                                    ; e627: 2c 01 d8    ,..
    bpl ce647                                                         ; e62a: 10 1b       ..
    lda adlc_b_tx                                                     ; e62c: ad 02 d8    ...
    sta (mem_ptr_lo),y                                                ; e62f: 91 80       ..
    iny                                                               ; e631: c8          .
    lda adlc_b_tx                                                     ; e632: ad 02 d8    ...
    sta (mem_ptr_lo),y                                                ; e635: 91 80       ..
    iny                                                               ; e637: c8          .
    bne ce624                                                         ; e638: d0 ea       ..
    inc mem_ptr_hi                                                    ; e63a: e6 81       ..
    lda mem_ptr_hi                                                    ; e63c: a5 81       ..
    cmp top_ram_page                                                  ; e63e: c5 82       ..
    bcc ce624                                                         ; e640: 90 e2       ..
; &e642 referenced 5 times by &e60c, &e61a, &e656, &e675, &e67a
.ce642
    pla                                                               ; e642: 68          h
    pla                                                               ; e643: 68          h
    jmp main_loop                                                     ; e644: 4c 51 e0    LQ.

; &e647 referenced 1 time by &e62a
.ce647
    lda #0                                                            ; e647: a9 00       ..
    sta adlc_b_cr1                                                    ; e649: 8d 00 d8    ...
    lda #&84                                                          ; e64c: a9 84       ..
    sta adlc_b_cr2                                                    ; e64e: 8d 01 d8    ...
    lda #2                                                            ; e651: a9 02       ..
    bit adlc_b_cr2                                                    ; e653: 2c 01 d8    ,..
    beq ce642                                                         ; e656: f0 ea       ..
    bpl ce660                                                         ; e658: 10 06       ..
    lda adlc_b_tx                                                     ; e65a: ad 02 d8    ...
    sta (mem_ptr_lo),y                                                ; e65d: 91 80       ..
    iny                                                               ; e65f: c8          .
; &e660 referenced 1 time by &e658
.ce660
    tya                                                               ; e660: 98          .
    tax                                                               ; e661: aa          .
    and #&fe                                                          ; e662: 29 fe       ).
    sta tx_end_lo                                                     ; e664: 8d 00 02    ...
    lda tx_src_net                                                    ; e667: ad 5d 04    .].
    bne ce672                                                         ; e66a: d0 06       ..
    lda net_num_b                                                     ; e66c: ad 00 d0    ...
    sta tx_src_net                                                    ; e66f: 8d 5d 04    .].
; &e672 referenced 1 time by &e66a
.ce672
    ldy tx_dst_net                                                    ; e672: ac 5b 04    .[.
    beq ce642                                                         ; e675: f0 cb       ..
    lda reachable_via_a,y                                             ; e677: b9 5a 03    .Z.
    beq ce642                                                         ; e67a: f0 c6       ..
    cpy net_num_a                                                     ; e67c: cc 00 c0    ...
    bne ce686                                                         ; e67f: d0 05       ..
    lda #0                                                            ; e681: a9 00       ..
    sta tx_dst_net                                                    ; e683: 8d 5b 04    .[.
; &e686 referenced 1 time by &e67f
.ce686
    lda mem_ptr_hi                                                    ; e686: a5 81       ..
    sta tx_end_hi                                                     ; e688: 8d 01 02    ...
    lda #4                                                            ; e68b: a9 04       ..
    sta mem_ptr_hi                                                    ; e68d: 85 81       ..
    rts                                                               ; e68f: 60          `

; ***************************************************************************************
; Wait for ADLC B's line to go idle (CSMA) or escape
; 
; Byte-for-byte mirror of wait_adlc_a_idle (&E6DC) with adlc_a_*
; replaced by adlc_b_*. Same pre-transmit carrier-sense semantics:
; wait for SR2 bit 2 (Rx Idle), back off on AP/RDA, escape to main
; loop on ~131K-iteration timeout.
; 
; Called from four sites: reset (&E04B), &E0D5, &E211, &E330.
; &e690 referenced 4 times by &e04b, &e0d5, &e211, &e330
.wait_adlc_b_idle
    lda #0                                                            ; e690: a9 00       ..
    sta ctr24_lo                                                      ; e692: 8d 14 02    ...
    sta ctr24_mid                                                     ; e695: 8d 15 02    ...
    lda #&fe                                                          ; e698: a9 fe       ..
    sta ctr24_hi                                                      ; e69a: 8d 16 02    ...
    lda adlc_b_cr2                                                    ; e69d: ad 01 d8    ...
    ldy #&e7                                                          ; e6a0: a0 e7       ..
; &e6a2 referenced 3 times by &e6c2, &e6c7, &e6cc
.ce6a2
    lda #&67 ; 'g'                                                    ; e6a2: a9 67       .g
    sta adlc_b_cr2                                                    ; e6a4: 8d 01 d8    ...
    lda #4                                                            ; e6a7: a9 04       ..
    bit adlc_b_cr2                                                    ; e6a9: 2c 01 d8    ,..
    bne ce6d3                                                         ; e6ac: d0 25       .%
    lda adlc_b_cr2                                                    ; e6ae: ad 01 d8    ...
    and #&81                                                          ; e6b1: 29 81       ).
    beq ce6bf                                                         ; e6b3: f0 0a       ..
    lda #&c2                                                          ; e6b5: a9 c2       ..
    sta adlc_b_cr1                                                    ; e6b7: 8d 00 d8    ...
    lda #&82                                                          ; e6ba: a9 82       ..
    sta adlc_b_cr1                                                    ; e6bc: 8d 00 d8    ...
; &e6bf referenced 1 time by &e6b3
.ce6bf
    inc ctr24_lo                                                      ; e6bf: ee 14 02    ...
    bne ce6a2                                                         ; e6c2: d0 de       ..
    inc ctr24_mid                                                     ; e6c4: ee 15 02    ...
    bne ce6a2                                                         ; e6c7: d0 d9       ..
    inc ctr24_hi                                                      ; e6c9: ee 16 02    ...
    bne ce6a2                                                         ; e6cc: d0 d4       ..
    pla                                                               ; e6ce: 68          h
    pla                                                               ; e6cf: 68          h
    jmp main_loop                                                     ; e6d0: 4c 51 e0    LQ.

; &e6d3 referenced 1 time by &e6ac
.ce6d3
    sty adlc_b_cr2                                                    ; e6d3: 8c 01 d8    ...
    lda #&44 ; 'D'                                                    ; e6d6: a9 44       .D
    sta adlc_b_cr1                                                    ; e6d8: 8d 00 d8    ...
    rts                                                               ; e6db: 60          `

; ***************************************************************************************
; Wait for ADLC A's line to go idle (CSMA) or escape
; 
; Pre-transmit carrier-sense: polls ADLC A's SR2 until the Rx Idle
; bit goes high (SR2 bit 2 = 15+ consecutive 1s received, i.e. the
; line is quiet and it is safe to start a frame). A 24-bit timeout
; counter at ctr24_lo/mid/hi (&0214-&0216) starts at &00_00_FE and
; increments LSB-first; overflow takes ~131K iterations, a few
; seconds at typical bus speeds.
; 
; Each iteration re-primes CR2 with &67 (clear TX/RX status,
; FC_TDRA, 2/1-byte, PSE) then reads SR2. Three outcomes:
; 
;   * SR2 bit 2 set (Rx Idle): line is quiet. Arm CR2=&E7 and
;     CR1=&44, RTS -- caller proceeds to transmit.
; 
;   * SR2 bit 0 or bit 7 set (AP or RDA): another station is
;     sending into this ADLC. Back off by cycling CR1 through
;     &C2 -> &82 (reset TX without touching RX) and keep polling.
;     The Bridge is not the right place to assert on a busy line.
; 
;   * Timeout (counter overflows without ever seeing Rx Idle):
;     PLA/PLA discards the caller's saved return address from the
;     stack and JMP &E051 escapes into the main Bridge loop. The
;     code between the caller's JSR and the main loop is skipped
;     entirely. See docs/analysis/escape-to-main-control-flow.md.
; 
; Called from four sites, always immediately before a transmit:
; reset (&E03B, before transmit_frame_a), &E0AA, &E1AF, &E392.
; Timeout counter = &00_00_FE (~131K iterations)
; &e6dc referenced 4 times by &e03b, &e0aa, &e1af, &e392
.wait_adlc_a_idle
    lda #0                                                            ; e6dc: a9 00       ..
    sta ctr24_lo                                                      ; e6de: 8d 14 02    ...
    sta ctr24_mid                                                     ; e6e1: 8d 15 02    ...
    lda #&fe                                                          ; e6e4: a9 fe       ..
    sta ctr24_hi                                                      ; e6e6: 8d 16 02    ...
; (spurious SR2 read; Z/N set but A overwritten below)
    lda adlc_a_cr2                                                    ; e6e9: ad 01 c8    ...
; Y = &E7: CR2 value written on Rx-Idle exit
    ldy #&e7                                                          ; e6ec: a0 e7       ..
; Re-prime CR2 = &67: clear status, FC_TDRA etc.
; &e6ee referenced 3 times by &e70e, &e713, &e718
.ce6ee
    lda #&67 ; 'g'                                                    ; e6ee: a9 67       .g
    sta adlc_a_cr2                                                    ; e6f0: 8d 01 c8    ...
; A = &04 for the BIT: test SR2 bit 2 (Rx Idle)
    lda #4                                                            ; e6f3: a9 04       ..
    bit adlc_a_cr2                                                    ; e6f5: 2c 01 c8    ,..
; Rx Idle -> line quiet, exit to transmit via &E71F
    bne ce71f                                                         ; e6f8: d0 25       .%
    lda adlc_a_cr2                                                    ; e6fa: ad 01 c8    ...
; Mask AP (bit 0) and RDA (bit 7) -- incoming data?
    and #&81                                                          ; e6fd: 29 81       ).
; Neither -> line busy but nothing for us, keep polling
    beq ce70b                                                         ; e6ff: f0 0a       ..
; CR1 tickle: reset TX while another station sends
    lda #&c2                                                          ; e701: a9 c2       ..
    sta adlc_a_cr1                                                    ; e703: 8d 00 c8    ...
    lda #&82                                                          ; e706: a9 82       ..
    sta adlc_a_cr1                                                    ; e708: 8d 00 c8    ...
; Bump 24-bit timeout counter (LSB first)
; &e70b referenced 1 time by &e6ff
.ce70b
    inc ctr24_lo                                                      ; e70b: ee 14 02    ...
    bne ce6ee                                                         ; e70e: d0 de       ..
    inc ctr24_mid                                                     ; e710: ee 15 02    ...
    bne ce6ee                                                         ; e713: d0 d9       ..
    inc ctr24_hi                                                      ; e715: ee 16 02    ...
    bne ce6ee                                                         ; e718: d0 d4       ..
; Timeout: drop caller's return address from stack...
    pla                                                               ; e71a: 68          h
    pla                                                               ; e71b: 68          h
; ...and jump straight to the main Bridge loop
    jmp main_loop                                                     ; e71c: 4c 51 e0    LQ.

; Rx Idle seen: arm CR2 and CR1 ready for transmit
; &e71f referenced 1 time by &e6f8
.ce71f
    sty adlc_a_cr2                                                    ; e71f: 8c 01 c8    ...
    lda #&44 ; 'D'                                                    ; e722: a9 44       .D
    sta adlc_a_cr1                                                    ; e724: 8d 00 c8    ...
; Normal return: caller may now transmit
    rts                                                               ; e727: 60          `

    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e728: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e734: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e740: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e74c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e758: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e764: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e770: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e77c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e788: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e794: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e7a0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e7ac: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e7b8: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e7c4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e7d0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e7dc: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e7e8: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e7f4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e800: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e80c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e818: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e824: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e830: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e83c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e848: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e854: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e860: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e86c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e878: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e884: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e890: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e89c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e8a8: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e8b4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e8c0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e8cc: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e8d8: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e8e4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e8f0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e8fc: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e908: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e914: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e920: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e92c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e938: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e944: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e950: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e95c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e968: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e974: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e980: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e98c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e998: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e9a4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e9b0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e9bc: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e9c8: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e9d4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e9e0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e9ec: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; e9f8: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ea04: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ea10: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ea1c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ea28: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ea34: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ea40: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ea4c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ea58: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ea64: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ea70: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ea7c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ea88: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ea94: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eaa0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eaac: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eab8: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eac4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ead0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eadc: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eae8: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eaf4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eb00: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eb0c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eb18: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eb24: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eb30: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eb3c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eb48: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eb54: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eb60: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eb6c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eb78: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eb84: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eb90: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eb9c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eba8: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ebb4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ebc0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ebcc: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ebd8: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ebe4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ebf0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ebfc: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ec08: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ec14: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ec20: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ec2c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ec38: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ec44: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ec50: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ec5c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ec68: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ec74: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ec80: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ec8c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ec98: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eca4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ecb0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ecbc: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ecc8: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ecd4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ece0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ecec: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ecf8: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ed04: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ed10: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ed1c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ed28: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ed34: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ed40: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ed4c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ed58: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ed64: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ed70: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ed7c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ed88: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ed94: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eda0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; edac: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; edb8: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; edc4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; edd0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eddc: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ede8: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; edf4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ee00: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ee0c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ee18: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ee24: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ee30: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ee3c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ee48: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ee54: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ee60: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ee6c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ee78: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ee84: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ee90: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ee9c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eea8: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eeb4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eec0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eecc: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eed8: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eee4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eef0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; eefc: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ef08: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ef14: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ef20: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ef2c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ef38: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ef44: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ef50: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ef5c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ef68: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ef74: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ef80: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ef8c: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ef98: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; efa4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; efb0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; efbc: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; efc8: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; efd4: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; efe0: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; efec: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff                       ; eff8: ff ff ff... ...

; ***************************************************************************************
; Self-test entry (IRQ/BRK vector target)
; 
; Invoked by pressing the self-test push-button on the 6502 ~IRQ
; line (and, implicitly, by any BRK instruction in the ROM). Runs
; through a sequence of hardware checks, signalling any failure
; via self_test_fail at &F2C7 with an error code in A.
; 
; Not to be pressed while the Bridge is connected to a live
; network: the self-test reconfigures the ADLCs and drives their
; control registers in ways that will disturb any in-flight frames.
; Typical usage is with a loopback cable between the two Econet
; ports.
; Disable interrupts during self-test
.self_test
    sei                                                               ; f000: 78          x
; Clear &03 (self-test scratch)
    lda #0                                                            ; f001: a9 00       ..
    sta l0003                                                         ; f003: 85 03       ..
; ***************************************************************************************
; Reset both ADLCs and light the status LED
; 
; Byte-for-byte identical to the adlc_*_full_reset pair except for
; one crucial detail: CR3 is programmed to &80 (bit 7 set) instead
; of &00. CR3 bit 7 is the MC6854's LOC/DTR control bit — but the
; pin it drives is inverted: when the control bit is HIGH, the pin
; output goes LOW. On ADLC B (IC18) that pin sinks the low side of
; the front-panel status LED (which has its high side tied through
; a resistor to Vcc), so CR3 bit 7 = 1 pulls current through the
; LED and lights it. ADLC A's LOC/DTR pin is not wired and gets the
; same write for code symmetry only.
; 
; Re-entered at &F26C after certain test paths need to reset the
; chips again; the LED stays lit until a normal reset runs
; adlc_b_full_reset and clears CR3.
; CR1=&C1: reset TX+RX, AC=1 (both ADLCs)
; &f005 referenced 1 time by &f26c
.self_test_reset_adlcs
    lda #&c1                                                          ; f005: a9 c1       ..
    sta adlc_a_cr1                                                    ; f007: 8d 00 c8    ...
    sta adlc_b_cr1                                                    ; f00a: 8d 00 d8    ...
; CR4=&1E (both): 8-bit RX, abort extend, NRZ
    lda #&1e                                                          ; f00d: a9 1e       ..
    sta adlc_a_tx2                                                    ; f00f: 8d 03 c8    ...
    sta adlc_b_tx2                                                    ; f012: 8d 03 d8    ...
; CR3=&80 (both): bit 7=1 -> LOC/DTR pin LOW (inverted)
    lda #&80                                                          ; f015: a9 80       ..
    sta adlc_a_cr2                                                    ; f017: 8d 01 c8    ...
; On ADLC B -> LED ON; on ADLC A pin NC, no effect
    lda #&80                                                          ; f01a: a9 80       ..
    sta adlc_b_cr2                                                    ; f01c: 8d 01 d8    ...
; CR1=&82 (both): TX in reset, AC=0; CR3 values persist
    lda #&82                                                          ; f01f: a9 82       ..
    sta adlc_a_cr1                                                    ; f021: 8d 00 c8    ...
    sta adlc_b_cr1                                                    ; f024: 8d 00 d8    ...
; CR2=&67 (both): clear status, FC_TDRA, 2/1-byte, PSE
    lda #&67 ; 'g'                                                    ; f027: a9 67       .g
    sta adlc_a_cr2                                                    ; f029: 8d 01 c8    ...
    sta adlc_b_cr2                                                    ; f02c: 8d 01 d8    ...
; ***************************************************************************************
; Zero-page integrity test (&00-&02)
; 
; Writes &55 to &00, &01, &02 and reads them back; then &AA and
; reads back. Failure jumps to self_test_fail with A=1.
; 
; Tests only the three ZP bytes that are used as scratch by the
; later self-test stages (ROM checksum, RAM scan). A full ZP test
; isn't needed — the main reset handler has already exercised ZP
; indirectly via the RAM test.
; First pattern: &55
; &f02f referenced 1 time by &f289
.self_test_zp
    lda #&55 ; 'U'                                                    ; f02f: a9 55       .U
; &f031 referenced 1 time by &f049
.loop_cf031
    sta l0000                                                         ; f031: 85 00       ..
    sta l0001                                                         ; f033: 85 01       ..
    sta l0002                                                         ; f035: 85 02       ..
    cmp l0000                                                         ; f037: c5 00       ..
    bne cf09d                                                         ; f039: d0 62       .b
    cmp l0001                                                         ; f03b: c5 01       ..
    bne cf09d                                                         ; f03d: d0 5e       .^
    cmp l0002                                                         ; f03f: c5 02       ..
    bne cf09d                                                         ; f041: d0 5a       .Z
; If pattern was &AA, ZP test done
    cmp #&aa                                                          ; f043: c9 aa       ..
    beq self_test_rom_checksum                                        ; f045: f0 05       ..
; Second pattern: &AA, loop back through the test
    lda #&aa                                                          ; f047: a9 aa       ..
    jmp loop_cf031                                                    ; f049: 4c 31 f0    L1.

; 
; ***************************************************************************************
; ROM checksum
; 
; Sums every byte of the 8 KiB ROM modulo 256 using a running A
; accumulator. Expected total is &55; on mismatch, jumps to
; self_test_fail with A=2.
; 
; Runtime pointer in &00/&01 starts at &E000; &02 holds the page
; counter (32 pages = 8 KiB).
; Pointer &00/&01 = &E000 (ROM base)
; &f04c referenced 1 time by &f045
.self_test_rom_checksum
    lda #0                                                            ; f04c: a9 00       ..
    sta l0000                                                         ; f04e: 85 00       ..
; &02 = 32 (pages to sum)
    lda #&20 ; ' '                                                    ; f050: a9 20       .
    sta l0002                                                         ; f052: 85 02       ..
    lda #&e0                                                          ; f054: a9 e0       ..
    sta l0001                                                         ; f056: 85 01       ..
; Running total starts at A=Y=0
    ldy #0                                                            ; f058: a0 00       ..
    tya                                                               ; f05a: 98          .              ; A=&00
; &f05b referenced 2 times by &f05f, &f065
.cf05b
    clc                                                               ; f05b: 18          .
; Add next ROM byte to running sum
    adc (l0000),y                                                     ; f05c: 71 00       q.
    iny                                                               ; f05e: c8          .
    bne cf05b                                                         ; f05f: d0 fa       ..
; Advance to next page
    inc l0001                                                         ; f061: e6 01       ..
    dec l0002                                                         ; f063: c6 02       ..
    bne cf05b                                                         ; f065: d0 f4       ..
; Expected total: &55
    cmp #&55 ; 'U'                                                    ; f067: c9 55       .U
    beq self_test_ram_pattern                                         ; f069: f0 05       ..
; Fail code 2: ROM checksum
    lda #2                                                            ; f06b: a9 02       ..
    jmp self_test_fail                                                ; f06d: 4c c7 f2    L..

; ***************************************************************************************
; RAM pattern test: write &55/&AA to every byte, verify
; 
; Starting at address &0004 (skipping the three zero-page bytes
; reserved for the self-test workspace at &00/&01/&02), iterates
; through the full 8 KiB of RAM and checks that each byte can
; store both &55 and &AA. Pointer in (&00,&01) = &0000, Y starts
; at 4 and wraps, page count in &02 = &20 (32 pages = 8 KiB).
; 
; On mismatch, jumps to ram_test_fail at &F28C (note: a *different*
; failure handler from self_test_fail, because a broken RAM cannot
; use the normal blink-code loop which needs RAM workspace).
; &f070 referenced 1 time by &f069
.self_test_ram_pattern
    lda #0                                                            ; f070: a9 00       ..
    sta l0000                                                         ; f072: 85 00       ..
    lda #0                                                            ; f074: a9 00       ..
    sta l0001                                                         ; f076: 85 01       ..
    lda #&20 ; ' '                                                    ; f078: a9 20       .
    sta l0002                                                         ; f07a: 85 02       ..
    ldy #4                                                            ; f07c: a0 04       ..
; &f07e referenced 2 times by &f093, &f099
.cf07e
    lda #&55 ; 'U'                                                    ; f07e: a9 55       .U
    sta (l0000),y                                                     ; f080: 91 00       ..
    lda (l0000),y                                                     ; f082: b1 00       ..
    cmp #&55 ; 'U'                                                    ; f084: c9 55       .U
    bne cf09d                                                         ; f086: d0 15       ..
    lda #&aa                                                          ; f088: a9 aa       ..
    sta (l0000),y                                                     ; f08a: 91 00       ..
    lda (l0000),y                                                     ; f08c: b1 00       ..
    cmp #&aa                                                          ; f08e: c9 aa       ..
    bne cf09d                                                         ; f090: d0 0b       ..
    iny                                                               ; f092: c8          .
    bne cf07e                                                         ; f093: d0 e9       ..
    inc l0001                                                         ; f095: e6 01       ..
    dec l0002                                                         ; f097: c6 02       ..
    bne cf07e                                                         ; f099: d0 e3       ..
    beq self_test_ram_incr                                            ; f09b: f0 03       ..             ; ALWAYS branch

; &f09d referenced 6 times by &f039, &f03d, &f041, &f086, &f090, &f0c9
.cf09d
    jmp ram_test_fail                                                 ; f09d: 4c 8c f2    L..

; ***************************************************************************************
; RAM incrementing-pattern test: fill with X, read back
; 
; Second RAM test. Fills the whole 8 KiB with an incrementing byte
; pattern (X register cycles through 0..&FF and then reinitialised
; each page with a different offset, giving a distinctive pattern
; across the RAM that catches address-line faults). Then reads
; back and verifies.
; 
; Catches failures that a plain &55/&AA pattern would miss:
; particularly address-line shorts, where writing to (say) &0410
; and &0420 would land at the same cell and produce the same bytes
; under a uniform pattern but different bytes under this one.
; 
; On mismatch, jumps to ram_test_fail at &F28C.
; &f0a0 referenced 1 time by &f09b
.self_test_ram_incr
    lda #0                                                            ; f0a0: a9 00       ..
    sta l0001                                                         ; f0a2: 85 01       ..
    lda #&20 ; ' '                                                    ; f0a4: a9 20       .
    sta l0002                                                         ; f0a6: 85 02       ..
    ldy #4                                                            ; f0a8: a0 04       ..
    ldx #0                                                            ; f0aa: a2 00       ..
; &f0ac referenced 2 times by &f0b1, &f0b8
.cf0ac
    txa                                                               ; f0ac: 8a          .
    sta (l0000),y                                                     ; f0ad: 91 00       ..
    inx                                                               ; f0af: e8          .
    iny                                                               ; f0b0: c8          .
    bne cf0ac                                                         ; f0b1: d0 f9       ..
    inc l0001                                                         ; f0b3: e6 01       ..
    inx                                                               ; f0b5: e8          .
    dec l0002                                                         ; f0b6: c6 02       ..
    bne cf0ac                                                         ; f0b8: d0 f2       ..
    lda #0                                                            ; f0ba: a9 00       ..
    sta l0001                                                         ; f0bc: 85 01       ..
    lda #&20 ; ' '                                                    ; f0be: a9 20       .
    sta l0002                                                         ; f0c0: 85 02       ..
    ldy #4                                                            ; f0c2: a0 04       ..
    ldx #0                                                            ; f0c4: a2 00       ..
; &f0c6 referenced 2 times by &f0cd, &f0d4
.cf0c6
    txa                                                               ; f0c6: 8a          .
    cmp (l0000),y                                                     ; f0c7: d1 00       ..
    bne cf09d                                                         ; f0c9: d0 d2       ..
    inx                                                               ; f0cb: e8          .
    iny                                                               ; f0cc: c8          .
    bne cf0c6                                                         ; f0cd: d0 f7       ..
    inc l0001                                                         ; f0cf: e6 01       ..
    inx                                                               ; f0d1: e8          .
    dec l0002                                                         ; f0d2: c6 02       ..
    bne cf0c6                                                         ; f0d4: d0 f0       ..
; ***************************************************************************************
; Verify both ADLCs' register state after reset
; 
; Checks that both ADLCs show the expected register state after
; self_test_reset_adlcs has configured them. Tests specific bits
; of SR1 and SR2 on each chip (ADLC A bits from &C800/&C801,
; ADLC B bits from &D800/&D801).
; 
; Failure paths:
;   Code 3 (at &F107): ADLC A register-state mismatch
;   Code 4 (at &F102): ADLC B register-state mismatch
.self_test_adlc_state
    lda #&10                                                          ; f0d6: a9 10       ..
    bit adlc_a_cr1                                                    ; f0d8: 2c 00 c8    ,..
    beq cf105                                                         ; f0db: f0 28       .(
    lda #4                                                            ; f0dd: a9 04       ..
    bit adlc_a_cr2                                                    ; f0df: 2c 01 c8    ,..
    beq cf105                                                         ; f0e2: f0 21       .!
    lda #&20 ; ' '                                                    ; f0e4: a9 20       .
    bit adlc_a_cr2                                                    ; f0e6: 2c 01 c8    ,..
    bne cf105                                                         ; f0e9: d0 1a       ..
    lda #&10                                                          ; f0eb: a9 10       ..
    bit adlc_b_cr1                                                    ; f0ed: 2c 00 d8    ,..
    beq cf100                                                         ; f0f0: f0 0e       ..
    lda #4                                                            ; f0f2: a9 04       ..
    bit adlc_b_cr2                                                    ; f0f4: 2c 01 d8    ,..
    beq cf100                                                         ; f0f7: f0 07       ..
    lda #&20 ; ' '                                                    ; f0f9: a9 20       .
    bit adlc_b_cr2                                                    ; f0fb: 2c 01 d8    ,..
    beq self_test_loopback_a_to_b                                     ; f0fe: f0 0a       ..
; &f100 referenced 2 times by &f0f0, &f0f7
.cf100
    lda #4                                                            ; f100: a9 04       ..
    jmp self_test_fail                                                ; f102: 4c c7 f2    L..

; &f105 referenced 3 times by &f0db, &f0e2, &f0e9
.cf105
    lda #3                                                            ; f105: a9 03       ..
    jmp self_test_fail                                                ; f107: 4c c7 f2    L..

; ***************************************************************************************
; Loopback test: transmit on ADLC A, receive on ADLC B
; 
; Assumes a loopback cable is connected between the two Econet
; ports. Reconfigures ADLC A for transmit (CR1=&44) and ADLC B for
; receive (CR1=&82), then sends a sequence of bytes out A and
; verifies they are received on B in the correct order.
; 
; Checks each byte against an expected value (X register,
; incrementing) and confirms the Frame Valid bit at end of frame.
; 
; Failure: Code 5 at &F153 -- TX on A or RX on B didn't match.
; &f10a referenced 1 time by &f0fe
.self_test_loopback_a_to_b
    lda #&c0                                                          ; f10a: a9 c0       ..
    sta adlc_a_cr1                                                    ; f10c: 8d 00 c8    ...
    sta adlc_b_cr1                                                    ; f10f: 8d 00 d8    ...
    lda #&82                                                          ; f112: a9 82       ..
    sta adlc_b_cr1                                                    ; f114: 8d 00 d8    ...
    lda #&e7                                                          ; f117: a9 e7       ..
    sta adlc_a_cr2                                                    ; f119: 8d 01 c8    ...
    lda #&44 ; 'D'                                                    ; f11c: a9 44       .D
    sta adlc_a_cr1                                                    ; f11e: 8d 00 c8    ...
    ldy #0                                                            ; f121: a0 00       ..
    ldx #0                                                            ; f123: a2 00       ..
; &f125 referenced 1 time by &f137
.loop_cf125
    jsr wait_adlc_a_irq                                               ; f125: 20 e4 e3     ..
    bit adlc_a_cr1                                                    ; f128: 2c 00 c8    ,..
    bvc cf151                                                         ; f12b: 50 24       P$
    sty adlc_a_tx                                                     ; f12d: 8c 02 c8    ...
    iny                                                               ; f130: c8          .
    sty adlc_a_tx                                                     ; f131: 8c 02 c8    ...
    iny                                                               ; f134: c8          .
    cpy #8                                                            ; f135: c0 08       ..
    bne loop_cf125                                                    ; f137: d0 ec       ..
    jsr wait_adlc_b_irq                                               ; f139: 20 ea e3     ..
    lda #1                                                            ; f13c: a9 01       ..
    bit adlc_b_cr2                                                    ; f13e: 2c 01 d8    ,..
    beq cf151                                                         ; f141: f0 0e       ..
    cpx adlc_b_tx                                                     ; f143: ec 02 d8    ...
    bne cf151                                                         ; f146: d0 09       ..
    inx                                                               ; f148: e8          .
    jsr wait_adlc_b_irq                                               ; f149: 20 ea e3     ..
    bit adlc_b_cr2                                                    ; f14c: 2c 01 d8    ,..
    bmi cf156                                                         ; f14f: 30 05       0.
; &f151 referenced 12 times by &f12b, &f141, &f146, &f159, &f162, &f172, &f177, &f17d, &f18f, &f194, &f19a, &f1a9
.cf151
    lda #5                                                            ; f151: a9 05       ..
    jmp self_test_fail                                                ; f153: 4c c7 f2    L..

; &f156 referenced 1 time by &f14f
.cf156
    cpx adlc_b_tx                                                     ; f156: ec 02 d8    ...
    bne cf151                                                         ; f159: d0 f6       ..
    inx                                                               ; f15b: e8          .
; &f15c referenced 1 time by &f182
.cf15c
    jsr wait_adlc_a_irq                                               ; f15c: 20 e4 e3     ..
    bit adlc_a_cr1                                                    ; f15f: 2c 00 c8    ,..
    bvc cf151                                                         ; f162: 50 ed       P.
    sty adlc_a_tx                                                     ; f164: 8c 02 c8    ...
    iny                                                               ; f167: c8          .
    sty adlc_a_tx                                                     ; f168: 8c 02 c8    ...
    iny                                                               ; f16b: c8          .
    jsr wait_adlc_b_irq                                               ; f16c: 20 ea e3     ..
    bit adlc_b_cr2                                                    ; f16f: 2c 01 d8    ,..
    bpl cf151                                                         ; f172: 10 dd       ..
    cpx adlc_b_tx                                                     ; f174: ec 02 d8    ...
    bne cf151                                                         ; f177: d0 d8       ..
    inx                                                               ; f179: e8          .
    cpx adlc_b_tx                                                     ; f17a: ec 02 d8    ...
    bne cf151                                                         ; f17d: d0 d2       ..
    inx                                                               ; f17f: e8          .
    cpy #0                                                            ; f180: c0 00       ..
    bne cf15c                                                         ; f182: d0 d8       ..
    lda #&3f ; '?'                                                    ; f184: a9 3f       .?
    sta adlc_a_cr2                                                    ; f186: 8d 01 c8    ...
; &f189 referenced 1 time by &f19f
.loop_cf189
    jsr wait_adlc_b_irq                                               ; f189: 20 ea e3     ..
    bit adlc_b_cr2                                                    ; f18c: 2c 01 d8    ,..
    bpl cf151                                                         ; f18f: 10 c0       ..
    cpx adlc_b_tx                                                     ; f191: ec 02 d8    ...
    bne cf151                                                         ; f194: d0 bb       ..
    inx                                                               ; f196: e8          .
    cpx adlc_b_tx                                                     ; f197: ec 02 d8    ...
    bne cf151                                                         ; f19a: d0 b5       ..
    inx                                                               ; f19c: e8          .
    cpx #0                                                            ; f19d: e0 00       ..
    bne loop_cf189                                                    ; f19f: d0 e8       ..
    jsr wait_adlc_b_irq                                               ; f1a1: 20 ea e3     ..
    lda #2                                                            ; f1a4: a9 02       ..
    bit adlc_b_cr2                                                    ; f1a6: 2c 01 d8    ,..
    beq cf151                                                         ; f1a9: f0 a6       ..
; ***************************************************************************************
; Loopback test: transmit on ADLC B, receive on ADLC A
; 
; Mirror of self_test_loopback_a_to_b. ADLC B transmits, ADLC A
; receives, same byte-sequence verification.
; 
; Failure: Code 6 at &F1F4.
.self_test_loopback_b_to_a
    lda #&c0                                                          ; f1ab: a9 c0       ..
    sta adlc_a_cr1                                                    ; f1ad: 8d 00 c8    ...
    sta adlc_b_cr1                                                    ; f1b0: 8d 00 d8    ...
    lda #&82                                                          ; f1b3: a9 82       ..
    sta adlc_a_cr1                                                    ; f1b5: 8d 00 c8    ...
    lda #&e7                                                          ; f1b8: a9 e7       ..
    sta adlc_b_cr2                                                    ; f1ba: 8d 01 d8    ...
    lda #&44 ; 'D'                                                    ; f1bd: a9 44       .D
    sta adlc_b_cr1                                                    ; f1bf: 8d 00 d8    ...
    ldy #0                                                            ; f1c2: a0 00       ..
    ldx #0                                                            ; f1c4: a2 00       ..
; &f1c6 referenced 1 time by &f1d8
.loop_cf1c6
    jsr wait_adlc_b_irq                                               ; f1c6: 20 ea e3     ..
    bit adlc_b_cr1                                                    ; f1c9: 2c 00 d8    ,..
    bvc cf1f2                                                         ; f1cc: 50 24       P$
    sty adlc_b_tx                                                     ; f1ce: 8c 02 d8    ...
    iny                                                               ; f1d1: c8          .
    sty adlc_b_tx                                                     ; f1d2: 8c 02 d8    ...
    iny                                                               ; f1d5: c8          .
    cpy #8                                                            ; f1d6: c0 08       ..
    bne loop_cf1c6                                                    ; f1d8: d0 ec       ..
    jsr wait_adlc_a_irq                                               ; f1da: 20 e4 e3     ..
    lda #1                                                            ; f1dd: a9 01       ..
    bit adlc_a_cr2                                                    ; f1df: 2c 01 c8    ,..
    beq cf1f2                                                         ; f1e2: f0 0e       ..
    cpx adlc_a_tx                                                     ; f1e4: ec 02 c8    ...
    bne cf1f2                                                         ; f1e7: d0 09       ..
    inx                                                               ; f1e9: e8          .
    jsr wait_adlc_a_irq                                               ; f1ea: 20 e4 e3     ..
    bit adlc_a_cr2                                                    ; f1ed: 2c 01 c8    ,..
    bmi cf1f7                                                         ; f1f0: 30 05       0.
; &f1f2 referenced 12 times by &f1cc, &f1e2, &f1e7, &f1fa, &f203, &f213, &f218, &f21e, &f230, &f235, &f23b, &f24a
.cf1f2
    lda #6                                                            ; f1f2: a9 06       ..
    jmp self_test_fail                                                ; f1f4: 4c c7 f2    L..

; &f1f7 referenced 1 time by &f1f0
.cf1f7
    cpx adlc_a_tx                                                     ; f1f7: ec 02 c8    ...
    bne cf1f2                                                         ; f1fa: d0 f6       ..
    inx                                                               ; f1fc: e8          .
; &f1fd referenced 1 time by &f223
.cf1fd
    jsr wait_adlc_b_irq                                               ; f1fd: 20 ea e3     ..
    bit adlc_b_cr1                                                    ; f200: 2c 00 d8    ,..
    bvc cf1f2                                                         ; f203: 50 ed       P.
    sty adlc_b_tx                                                     ; f205: 8c 02 d8    ...
    iny                                                               ; f208: c8          .
    sty adlc_b_tx                                                     ; f209: 8c 02 d8    ...
    iny                                                               ; f20c: c8          .
    jsr wait_adlc_a_irq                                               ; f20d: 20 e4 e3     ..
    bit adlc_a_cr2                                                    ; f210: 2c 01 c8    ,..
    bpl cf1f2                                                         ; f213: 10 dd       ..
    cpx adlc_a_tx                                                     ; f215: ec 02 c8    ...
    bne cf1f2                                                         ; f218: d0 d8       ..
    inx                                                               ; f21a: e8          .
    cpx adlc_a_tx                                                     ; f21b: ec 02 c8    ...
    bne cf1f2                                                         ; f21e: d0 d2       ..
    inx                                                               ; f220: e8          .
    cpy #0                                                            ; f221: c0 00       ..
    bne cf1fd                                                         ; f223: d0 d8       ..
    lda #&3f ; '?'                                                    ; f225: a9 3f       .?
    sta adlc_b_cr2                                                    ; f227: 8d 01 d8    ...
; &f22a referenced 1 time by &f240
.loop_cf22a
    jsr wait_adlc_a_irq                                               ; f22a: 20 e4 e3     ..
    bit adlc_a_cr2                                                    ; f22d: 2c 01 c8    ,..
    bpl cf1f2                                                         ; f230: 10 c0       ..
    cpx adlc_a_tx                                                     ; f232: ec 02 c8    ...
    bne cf1f2                                                         ; f235: d0 bb       ..
    inx                                                               ; f237: e8          .
    cpx adlc_a_tx                                                     ; f238: ec 02 c8    ...
    bne cf1f2                                                         ; f23b: d0 b5       ..
    inx                                                               ; f23d: e8          .
    cpx #0                                                            ; f23e: e0 00       ..
    bne loop_cf22a                                                    ; f240: d0 e8       ..
    jsr wait_adlc_a_irq                                               ; f242: 20 e4 e3     ..
    lda #2                                                            ; f245: a9 02       ..
    bit adlc_a_cr2                                                    ; f247: 2c 01 c8    ,..
    beq cf1f2                                                         ; f24a: f0 a6       ..
; ***************************************************************************************
; Verify jumper-set network numbers match self-test expectations
; 
; Checks that net_num_a == 1 and net_num_b == 2. The self-test
; presumes a standard loopback-test configuration: the jumpers on
; the bridge board should be set for 1 and 2 respectively before
; the self-test button is pressed, so that the network numbers
; are predictable and the loopback tests can complete without
; colliding with anything else a tester might leave plugged in.
; 
; Failure paths:
;   Code 7 at &F255: net_num_a != 1
;   Code 8 at &F261: net_num_b != 2
.self_test_check_netnums
    lda net_num_a                                                     ; f24c: ad 00 c0    ...
    cmp #1                                                            ; f24f: c9 01       ..
    beq cf258                                                         ; f251: f0 05       ..
    lda #7                                                            ; f253: a9 07       ..
    jmp self_test_fail                                                ; f255: 4c c7 f2    L..

; &f258 referenced 1 time by &f251
.cf258
    lda net_num_b                                                     ; f258: ad 00 d0    ...
    cmp #2                                                            ; f25b: c9 02       ..
    beq self_test_pass_done                                           ; f25d: f0 05       ..
    lda #8                                                            ; f25f: a9 08       ..
    jmp self_test_fail                                                ; f261: 4c c7 f2    L..

; ***************************************************************************************
; End-of-pass: toggle scratch flag and loop for another pass
; 
; Reached when every test in a pass has succeeded. The self-test
; doesn't stop -- it loops indefinitely until reset. Toggles bit 7
; of &0003 (the self-test scratch byte) via EOR #&FF; if bit 7 is
; set after the toggle, JMPs to self_test_reset_adlcs for another
; full pass. Otherwise falls through to a slower test variant that
; resets ADLCs differently before re-entering the ZP test.
; 
; Two-pass structure lets the operator see continuous LED activity
; (via the self-test ADLC reset's CR3=&80) for as long as the test
; is running, with minor variation between passes catching some
; intermittent faults.
; &f264 referenced 1 time by &f25d
.self_test_pass_done
    lda l0003                                                         ; f264: a5 03       ..
    eor #&ff                                                          ; f266: 49 ff       I.
    sta l0003                                                         ; f268: 85 03       ..
    bmi cf26f                                                         ; f26a: 30 03       0.
    jmp self_test_reset_adlcs                                         ; f26c: 4c 05 f0    L..

; &f26f referenced 1 time by &f26a
.cf26f
    lda #&c1                                                          ; f26f: a9 c1       ..
    sta adlc_a_cr1                                                    ; f271: 8d 00 c8    ...
    lda #0                                                            ; f274: a9 00       ..
    sta adlc_a_cr2                                                    ; f276: 8d 01 c8    ...
    lda #&82                                                          ; f279: a9 82       ..
    sta adlc_a_cr1                                                    ; f27b: 8d 00 c8    ...
    sta adlc_b_cr1                                                    ; f27e: 8d 00 d8    ...
    lda #&67 ; 'g'                                                    ; f281: a9 67       .g
    sta adlc_a_cr2                                                    ; f283: 8d 01 c8    ...
    sta adlc_b_cr2                                                    ; f286: 8d 01 d8    ...
    jmp self_test_zp                                                  ; f289: 4c 2f f0    L/.

; ***************************************************************************************
; RAM-failure blink pattern (does not use RAM)
; 
; Reached from any of the three RAM tests on failure -- ZP test,
; pattern RAM test, incrementing RAM test. This handler can't
; use RAM for counting blinks (if RAM is broken, reading/writing
; RAM is exactly what's untrustworthy), so it generates its blink
; pattern from ROM-based DEC abs,X instructions that exercise the
; CPU for timing without touching RAM.
; 
; Sets CR1=1 (AC=1) so writes to adlc_a_cr2 target CR3. Alternates
; CR3 between &00 (LED off) and &80 (LED on) in an infinite loop
; paced by DEX/DEY delays and by seven DEC instructions that
; read-modify-write (but actually just read, since writes to ROM
; are ignored) bytes in the ROM starting at the reset vector.
; 
; Continues forever; the operator infers "the RAM is bad" from the
; fact that the LED is blinking but no specific error code can be
; counted out -- distinct from the more structured blink patterns
; produced by self_test_fail with codes 2-8.
; &f28c referenced 1 time by &f09d
.ram_test_fail
    ldx #1                                                            ; f28c: a2 01       ..
    stx adlc_a_cr1                                                    ; f28e: 8e 00 c8    ...
; &f291 referenced 1 time by &f2c4
.cf291
    ldx #0                                                            ; f291: a2 00       ..
    stx adlc_a_cr2                                                    ; f293: 8e 01 c8    ...
    ldx #0                                                            ; f296: a2 00       ..
    ldy #0                                                            ; f298: a0 00       ..
; &f29a referenced 2 times by &f29b, &f29e
.cf29a
    dex                                                               ; f29a: ca          .
    bne cf29a                                                         ; f29b: d0 fd       ..
    dey                                                               ; f29d: 88          .
    bne cf29a                                                         ; f29e: d0 fa       ..
    ldx #&80                                                          ; f2a0: a2 80       ..
    stx adlc_a_cr2                                                    ; f2a2: 8e 01 c8    ...
    ldy #0                                                            ; f2a5: a0 00       ..
    ldx #0                                                            ; f2a7: a2 00       ..
; &f2a9 referenced 2 times by &f2bf, &f2c2
.cf2a9
    dec reset,x                                                       ; f2a9: de 00 e0    ...
    dec reset,x                                                       ; f2ac: de 00 e0    ...
    dec reset,x                                                       ; f2af: de 00 e0    ...
    dec reset,x                                                       ; f2b2: de 00 e0    ...
    dec reset,x                                                       ; f2b5: de 00 e0    ...
    dec reset,x                                                       ; f2b8: de 00 e0    ...
    dec reset,x                                                       ; f2bb: de 00 e0    ...
    dex                                                               ; f2be: ca          .
    bne cf2a9                                                         ; f2bf: d0 e8       ..
    dey                                                               ; f2c1: 88          .
    bne cf2a9                                                         ; f2c2: d0 e5       ..
    jmp cf291                                                         ; f2c4: 4c 91 f2    L..

; ***************************************************************************************
; Self-test failure — signal error code via the LED
; 
; Common failure exit for every non-RAM self-test stage. Called
; with the error code in A. Saves two copies of the code in &00/&01
; then enters an infinite loop that blinks the LED (via CR3 bit 7
; on ADLC B, which is the pin that drives the front-panel LED)
; a count of times equal to the error code, separated by longer
; gaps.
; 
; Error code table:
; 
;   2   ROM checksum mismatch (self_test_rom_checksum at &F04C)
;   3   ADLC A register state wrong (self_test_adlc_state, &F107)
;   4   ADLC B register state wrong (self_test_adlc_state, &F102)
;   5   A-to-B loopback fail (self_test_loopback_a_to_b, &F153)
;   6   B-to-A loopback fail (self_test_loopback_b_to_a, &F1F4)
;   7   net_num_a != 1 (self_test_check_netnums, &F255)
;   8   net_num_b != 2 (self_test_check_netnums, &F261)
; 
; (Code 1 is not used: the zero-page integrity test's failure path
; routes to ram_test_fail via cf09d, not here, because any failure
; of the first three RAM tests means normal counting loops can't
; be trusted. ram_test_fail at &F28C uses a distinct ROM-only
; blink instead.)
; 
; Blink pattern: CR1=1 sets the ADLC's AC bit so writes to CR2's
; address hit CR3. The handler alternates CR3=&00 (LED off) and
; CR3=&80 (LED on) N times, where N = error code held in &01, with
; delay loops between each pulse. After each N-pulse burst, a fixed
; 8-pulse spacer pattern runs before the outer loop repeats. The
; operator counts pulses to identify the failed test.
; &f2c7 referenced 7 times by &f06d, &f102, &f107, &f153, &f1f4, &f255, &f261
.self_test_fail
    sta l0000                                                         ; f2c7: 85 00       ..
    sta l0001                                                         ; f2c9: 85 01       ..
    ldx #1                                                            ; f2cb: a2 01       ..
    stx adlc_a_cr1                                                    ; f2cd: 8e 00 c8    ...
; &f2d0 referenced 2 times by &f2f0, &f308
.cf2d0
    ldx #0                                                            ; f2d0: a2 00       ..
    stx adlc_a_cr2                                                    ; f2d2: 8e 01 c8    ...
    ldy #0                                                            ; f2d5: a0 00       ..
    ldx #0                                                            ; f2d7: a2 00       ..
; &f2d9 referenced 2 times by &f2da, &f2dd
.cf2d9
    dex                                                               ; f2d9: ca          .
    bne cf2d9                                                         ; f2da: d0 fd       ..
    dey                                                               ; f2dc: 88          .
    bne cf2d9                                                         ; f2dd: d0 fa       ..
    ldx #&80                                                          ; f2df: a2 80       ..
    stx adlc_a_cr2                                                    ; f2e1: 8e 01 c8    ...
    ldy #0                                                            ; f2e4: a0 00       ..
    ldx #0                                                            ; f2e6: a2 00       ..
; &f2e8 referenced 2 times by &f2e9, &f2ec
.cf2e8
    dex                                                               ; f2e8: ca          .
    bne cf2e8                                                         ; f2e9: d0 fd       ..
    dey                                                               ; f2eb: 88          .
    bne cf2e8                                                         ; f2ec: d0 fa       ..
    dec l0001                                                         ; f2ee: c6 01       ..
    bne cf2d0                                                         ; f2f0: d0 de       ..
    lda #8                                                            ; f2f2: a9 08       ..
    sta l0001                                                         ; f2f4: 85 01       ..
    ldy #0                                                            ; f2f6: a0 00       ..
    ldx #0                                                            ; f2f8: a2 00       ..
; &f2fa referenced 3 times by &f2fb, &f2fe, &f302
.cf2fa
    dex                                                               ; f2fa: ca          .
    bne cf2fa                                                         ; f2fb: d0 fd       ..
    dey                                                               ; f2fd: 88          .
    bne cf2fa                                                         ; f2fe: d0 fa       ..
    dec l0001                                                         ; f300: c6 01       ..
    bne cf2fa                                                         ; f302: d0 f6       ..
    lda l0000                                                         ; f304: a5 00       ..
    sta l0001                                                         ; f306: 85 01       ..
    jmp cf2d0                                                         ; f308: 4c d0 f2    L..

    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f30b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f317: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f323: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f32f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f33b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f347: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f353: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f35f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f36b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f377: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f383: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f38f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f39b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f3a7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f3b3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f3bf: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f3cb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f3d7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f3e3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f3ef: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f3fb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f407: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f413: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f41f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f42b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f437: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f443: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f44f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f45b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f467: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f473: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f47f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f48b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f497: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f4a3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f4af: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f4bb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f4c7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f4d3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f4df: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f4eb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f4f7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f503: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f50f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f51b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f527: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f533: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f53f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f54b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f557: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f563: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f56f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f57b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f587: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f593: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f59f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f5ab: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f5b7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f5c3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f5cf: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f5db: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f5e7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f5f3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f5ff: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f60b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f617: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f623: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f62f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f63b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f647: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f653: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f65f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f66b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f677: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f683: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f68f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f69b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f6a7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f6b3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f6bf: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f6cb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f6d7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f6e3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f6ef: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f6fb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f707: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f713: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f71f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f72b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f737: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f743: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f74f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f75b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f767: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f773: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f77f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f78b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f797: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f7a3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f7af: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f7bb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f7c7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f7d3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f7df: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f7eb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f7f7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f803: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f80f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f81b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f827: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f833: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f83f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f84b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f857: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f863: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f86f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f87b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f887: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f893: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f89f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f8ab: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f8b7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f8c3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f8cf: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f8db: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f8e7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f8f3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f8ff: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f90b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f917: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f923: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f92f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f93b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f947: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f953: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f95f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f96b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f977: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f983: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f98f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f99b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f9a7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f9b3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f9bf: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f9cb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f9d7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f9e3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f9ef: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; f9fb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fa07: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fa13: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fa1f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fa2b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fa37: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fa43: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fa4f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fa5b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fa67: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fa73: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fa7f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fa8b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fa97: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; faa3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; faaf: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fabb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fac7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fad3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fadf: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; faeb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; faf7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fb03: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fb0f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fb1b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fb27: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fb33: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fb3f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fb4b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fb57: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fb63: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fb6f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fb7b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fb87: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fb93: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fb9f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fbab: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fbb7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fbc3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fbcf: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fbdb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fbe7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fbf3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fbff: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fc0b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fc17: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fc23: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fc2f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fc3b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fc47: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fc53: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fc5f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fc6b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fc77: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fc83: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fc8f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fc9b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fca7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fcb3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fcbf: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fccb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fcd7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fce3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fcef: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fcfb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fd07: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fd13: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fd1f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fd2b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fd37: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fd43: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fd4f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fd5b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fd67: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fd73: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fd7f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fd8b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fd97: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fda3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fdaf: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fdbb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fdc7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fdd3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fddf: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fdeb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fdf7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fe03: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fe0f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fe1b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fe27: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fe33: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fe3f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fe4b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fe57: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fe63: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fe6f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fe7b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fe87: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fe93: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fe9f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; feab: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; feb7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fec3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fecf: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fedb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fee7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; fef3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; feff: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ff0b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ff17: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ff23: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ff2f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ff3b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ff47: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ff53: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ff5f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ff6b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ff77: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ff83: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ff8f: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ff9b: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ffa7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ffb3: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ffbf: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ffcb: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ffd7: ff ff ff... ...
    equb &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff   ; ffe3: ff ff ff... ...
    equb &ff, &46, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff, &ff        ; ffef: ff 46 ff... .F.
    equw &ffff                                                        ; fffa: ff ff       ..             ; NMI vector
    equw reset                                                        ; fffc: 00 e0       ..             ; RESET vector
    equw self_test                                                    ; fffe: 00 f0       ..             ; IRQ/BRK vector
.pydis_end

    assert reset == &e000
    assert self_test == &f000

save pydis_start, pydis_end

; Label references by decreasing frequency:
;     adlc_a_cr2:                 39
;     adlc_b_cr2:                 34
;     adlc_a_cr1:                 32
;     adlc_b_cr1:                 29
;     adlc_a_tx:                  26
;     adlc_b_tx:                  26
;     mem_ptr_hi:                 23
;     mem_ptr_lo:                 23
;     rx_dst_stn:                 20
;     wait_adlc_a_irq:            19
;     wait_adlc_b_irq:            19
;     l0000:                      15
;     l0001:                      15
;     main_loop:                  14
;     net_num_a:                  13
;     cf151:                      12
;     cf1f2:                      12
;     net_num_b:                  12
;     rx_len:                     12
;     l0002:                      10
;     tx_src_net:                 10
;     rx_dst_net:                  8
;     tx_dst_net:                  8
;     ctr24_lo:                    7
;     pydis_start:                 7
;     reachable_via_a:             7
;     reachable_via_b:             7
;     reset:                       7
;     self_test_fail:              7
;     transmit_frame_a:            7
;     transmit_frame_b:            7
;     announce_flag:               6
;     cf09d:                       6
;     tx_end_hi:                   6
;     tx_end_lo:                   6
;     ce5b1:                       5
;     ce642:                       5
;     handshake_rx_a:              5
;     handshake_rx_b:              5
;     main_loop_poll:              5
;     tx_ctrl:                     5
;     announce_count:              4
;     announce_tmr_hi:             4
;     announce_tmr_lo:             4
;     build_query_response:        4
;     ctr24_hi:                    4
;     ctr24_mid:                   4
;     rx_frame_a_bail:             4
;     rx_frame_b_bail:             4
;     rx_query_net:                4
;     rx_src_net:                  4
;     tx_dst_stn:                  4
;     tx_port:                     4
;     wait_adlc_a_idle:            4
;     wait_adlc_b_idle:            4
;     ce6a2:                       3
;     ce6ee:                       3
;     cf105:                       3
;     cf2fa:                       3
;     init_reachable_nets:         3
;     l0003:                       3
;     top_ram_page:                3
;     tx_data0:                    3
;     adlc_a_listen:               2
;     adlc_a_tx2:                  2
;     adlc_b_listen:               2
;     adlc_b_tx2:                  2
;     build_announce_b:            2
;     ce4cc:                       2
;     ce523:                       2
;     ce593:                       2
;     ce624:                       2
;     cf05b:                       2
;     cf07e:                       2
;     cf0ac:                       2
;     cf0c6:                       2
;     cf100:                       2
;     cf29a:                       2
;     cf2a9:                       2
;     cf2d0:                       2
;     cf2d9:                       2
;     cf2e8:                       2
;     re_announce_done:            2
;     rx_a_forward:                2
;     rx_a_not_for_us:             2
;     rx_a_to_forward:             2
;     rx_b_forward:                2
;     rx_b_not_for_us:             2
;     rx_b_to_forward:             2
;     rx_ctrl:                     2
;     rx_frame_a_dispatch:         2
;     rx_frame_b_dispatch:         2
;     rx_port:                     2
;     stagger_delay:               2
;     tx_src_stn:                  2
;     adlc_a_full_reset:           1
;     adlc_b_full_reset:           1
;     ce05d:                       1
;     ce073:                       1
;     ce081:                       1
;     ce15c:                       1
;     ce169:                       1
;     ce1d3:                       1
;     ce2dd:                       1
;     ce2ea:                       1
;     ce354:                       1
;     ce4d4:                       1
;     ce4d9:                       1
;     ce4e9:                       1
;     ce506:                       1
;     ce52b:                       1
;     ce530:                       1
;     ce540:                       1
;     ce55d:                       1
;     ce5b6:                       1
;     ce5cf:                       1
;     ce5e1:                       1
;     ce5f5:                       1
;     ce647:                       1
;     ce660:                       1
;     ce672:                       1
;     ce686:                       1
;     ce6bf:                       1
;     ce6d3:                       1
;     ce70b:                       1
;     ce71f:                       1
;     cf156:                       1
;     cf15c:                       1
;     cf1f7:                       1
;     cf1fd:                       1
;     cf258:                       1
;     cf26f:                       1
;     cf291:                       1
;     loop_ce428:                  1
;     loop_ce44a:                  1
;     loop_ce44d:                  1
;     loop_ce44f:                  1
;     loop_cf031:                  1
;     loop_cf125:                  1
;     loop_cf189:                  1
;     loop_cf1c6:                  1
;     loop_cf22a:                  1
;     main_loop_idle:              1
;     ram_test_done:               1
;     ram_test_fail:               1
;     ram_test_loop:               1
;     re_announce_rearm:           1
;     re_announce_side_b:          1
;     rx_a_forward_ack_round:      1
;     rx_a_forward_done:           1
;     rx_a_forward_pair_loop:      1
;     rx_a_handle_80:              1
;     rx_a_handle_81:              1
;     rx_a_handle_82:              1
;     rx_a_learn_loop:             1
;     rx_b_forward_ack_round:      1
;     rx_b_forward_done:           1
;     rx_b_forward_pair_loop:      1
;     rx_b_handle_80:              1
;     rx_b_handle_81:              1
;     rx_b_handle_82:              1
;     rx_b_learn_loop:             1
;     rx_frame_a:                  1
;     rx_frame_a_drain:            1
;     rx_frame_a_end:              1
;     rx_frame_b:                  1
;     rx_frame_b_drain:            1
;     rx_frame_b_end:              1
;     rx_query_port:               1
;     rx_src_stn:                  1
;     self_test_loopback_a_to_b:   1
;     self_test_pass_done:         1
;     self_test_ram_incr:          1
;     self_test_ram_pattern:       1
;     self_test_reset_adlcs:       1
;     self_test_rom_checksum:      1
;     self_test_zp:                1

; Automatically generated labels:
;     ce05d
;     ce073
;     ce081
;     ce15c
;     ce169
;     ce1d3
;     ce2dd
;     ce2ea
;     ce354
;     ce4cc
;     ce4d4
;     ce4d9
;     ce4e9
;     ce506
;     ce523
;     ce52b
;     ce530
;     ce540
;     ce55d
;     ce593
;     ce5b1
;     ce5b6
;     ce5cf
;     ce5e1
;     ce5f5
;     ce624
;     ce642
;     ce647
;     ce660
;     ce672
;     ce686
;     ce6a2
;     ce6bf
;     ce6d3
;     ce6ee
;     ce70b
;     ce71f
;     cf05b
;     cf07e
;     cf09d
;     cf0ac
;     cf0c6
;     cf100
;     cf105
;     cf151
;     cf156
;     cf15c
;     cf1f2
;     cf1f7
;     cf1fd
;     cf258
;     cf26f
;     cf291
;     cf29a
;     cf2a9
;     cf2d0
;     cf2d9
;     cf2e8
;     cf2fa
;     l0000
;     l0001
;     l0002
;     l0003
;     loop_ce428
;     loop_ce44a
;     loop_ce44d
;     loop_ce44f
;     loop_cf031
;     loop_cf125
;     loop_cf189
;     loop_cf1c6
;     loop_cf22a

; Stats:
;     Total size (Code + Data) = 8192 bytes
;     Code                     = 2611 bytes (32%)
;     Data                     = 5581 bytes (68%)
;
;     Number of instructions   = 1117
;     Number of data bytes     = 5575 bytes
;     Number of data words     = 6 bytes
;     Number of string bytes   = 0 bytes
;     Number of strings        = 0
