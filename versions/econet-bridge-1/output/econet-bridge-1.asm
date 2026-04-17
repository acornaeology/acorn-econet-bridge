; Memory locations
l0000       = &0000
l0001       = &0001
l0002       = &0002
l0003       = &0003
mem_ptr_lo  = &0080
mem_ptr_hi  = &0081
top_ram_page = &0082
l0200       = &0200
l0201       = &0201
l0214       = &0214
l0215       = &0215
l0216       = &0216
l0228       = &0228
l0229       = &0229
l022a       = &022a
l022b       = &022b
l022c       = &022c
l023c       = &023c
l023d       = &023d
l023e       = &023e
l023f       = &023f
l0240       = &0240
l0241       = &0241
l0248       = &0248
l0249       = &0249
net_a_map   = &025a
net_b_map   = &035a
tx_dst_stn  = &045a
tx_dst_net  = &045b
tx_src_stn  = &045c
tx_src_net  = &045d
tx_ctrl     = &045e
tx_port     = &045f
tx_data0    = &0460
station_id_a = &c000
adlc_a_cr1  = &c800
adlc_a_cr2  = &c801
adlc_a_tx   = &c802
adlc_a_tx2  = &c803
station_id_b = &d000
adlc_b_cr1  = &d800
adlc_b_cr2  = &d801
adlc_b_tx   = &d802
adlc_b_tx2  = &d803

    org &e000

; &e000 referenced 7 times by &f2a9, &f2ac, &f2af, &f2b2, &f2b5, &f2b8, &f2bb
.pydis_start
.reset
    cli                                                               ; e000: 58          X
    cld                                                               ; e001: d8          .
    jsr init_station_maps                                             ; e002: 20 24 e4     $.
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
    sta l0229                                                         ; e035: 8d 29 02    .).
    jsr build_announce_b                                              ; e038: 20 58 e4     X.
    jsr sub_ce6dc                                                     ; e03b: 20 dc e6     ..
    jsr sub_ce517                                                     ; e03e: 20 17 e5     ..
    lda station_id_a                                                  ; e041: ad 00 c0    ...
    sta tx_data0                                                      ; e044: 8d 60 04    .`.
    lda #4                                                            ; e047: a9 04       ..
    sta mem_ptr_hi                                                    ; e049: 85 81       ..
    jsr sub_ce690                                                     ; e04b: 20 90 e6     ..
    jsr sub_ce4c0                                                     ; e04e: 20 c0 e4     ..
; &e051 referenced 14 times by &e0bf, &e0c7, &e13c, &e1d3, &e260, &e2bd, &e354, &e3e1, &e4d6, &e52d, &e5b3, &e644, &e6d0, &e71c
.ce051
    lda adlc_a_cr2                                                    ; e051: ad 01 c8    ...
    and #&81                                                          ; e054: 29 81       ).
    beq ce05d                                                         ; e056: f0 05       ..
    lda #&c2                                                          ; e058: a9 c2       ..
    sta adlc_a_cr1                                                    ; e05a: 8d 00 c8    ...
; &e05d referenced 1 time by &e056
.ce05d
    ldx #&82                                                          ; e05d: a2 82       ..
    stx adlc_a_cr1                                                    ; e05f: 8e 00 c8    ...
    ldy #&67 ; 'g'                                                    ; e062: a0 67       .g
    sty adlc_a_cr2                                                    ; e064: 8c 01 c8    ...
    lda adlc_b_cr2                                                    ; e067: ad 01 d8    ...
    and #&81                                                          ; e06a: 29 81       ).
    beq ce073                                                         ; e06c: f0 05       ..
    lda #&c2                                                          ; e06e: a9 c2       ..
    sta adlc_b_cr1                                                    ; e070: 8d 00 d8    ...
; &e073 referenced 1 time by &e06c
.ce073
    stx adlc_b_cr1                                                    ; e073: 8e 00 d8    ...
    sty adlc_b_cr2                                                    ; e076: 8c 01 d8    ...
; &e079 referenced 5 times by &e08c, &e091, &e096, &e144, &e2c5
.ce079
    bit adlc_b_cr1                                                    ; e079: 2c 00 d8    ,..
    bpl ce081                                                         ; e07c: 10 03       ..
    jmp ce263                                                         ; e07e: 4c 63 e2    Lc.

; &e081 referenced 1 time by &e07c
.ce081
    bit adlc_a_cr1                                                    ; e081: 2c 00 c8    ,..
    bpl ce089                                                         ; e084: 10 03       ..
    jmp ce0e2                                                         ; e086: 4c e2 e0    L..

; &e089 referenced 1 time by &e084
.ce089
    lda l0229                                                         ; e089: ad 29 02    .).
    beq ce079                                                         ; e08c: f0 eb       ..
    dec l022a                                                         ; e08e: ce 2a 02    .*.
    bne ce079                                                         ; e091: d0 e6       ..
    dec l022b                                                         ; e093: ce 2b 02    .+.
    bne ce079                                                         ; e096: d0 e1       ..
    jsr build_announce_b                                              ; e098: 20 58 e4     X.
    lda #&81                                                          ; e09b: a9 81       ..
    sta tx_ctrl                                                       ; e09d: 8d 5e 04    .^.
    bit l0229                                                         ; e0a0: 2c 29 02    ,).
    bmi ce0ca                                                         ; e0a3: 30 25       0%
    lda #&c2                                                          ; e0a5: a9 c2       ..
    sta adlc_b_cr1                                                    ; e0a7: 8d 00 d8    ...
    jsr sub_ce6dc                                                     ; e0aa: 20 dc e6     ..
    jsr sub_ce517                                                     ; e0ad: 20 17 e5     ..
    dec l022c                                                         ; e0b0: ce 2c 02    .,.
    beq ce0c2                                                         ; e0b3: f0 0d       ..
; &e0b5 referenced 1 time by &e0e0
.ce0b5
    lda #&80                                                          ; e0b5: a9 80       ..
    sta l022b                                                         ; e0b7: 8d 2b 02    .+.
    lda #0                                                            ; e0ba: a9 00       ..
    sta l022a                                                         ; e0bc: 8d 2a 02    .*.
    jmp ce051                                                         ; e0bf: 4c 51 e0    LQ.

; &e0c2 referenced 2 times by &e0b3, &e0de
.ce0c2
    lda #0                                                            ; e0c2: a9 00       ..
    sta l0229                                                         ; e0c4: 8d 29 02    .).
    jmp ce051                                                         ; e0c7: 4c 51 e0    LQ.

; &e0ca referenced 1 time by &e0a3
.ce0ca
    lda station_id_a                                                  ; e0ca: ad 00 c0    ...
    sta tx_data0                                                      ; e0cd: 8d 60 04    .`.
    lda #&c2                                                          ; e0d0: a9 c2       ..
    sta adlc_a_cr1                                                    ; e0d2: 8d 00 c8    ...
    jsr sub_ce690                                                     ; e0d5: 20 90 e6     ..
    jsr sub_ce4c0                                                     ; e0d8: 20 c0 e4     ..
    dec l022c                                                         ; e0db: ce 2c 02    .,.
    beq ce0c2                                                         ; e0de: f0 e2       ..
    bne ce0b5                                                         ; e0e0: d0 d3       ..             ; ALWAYS branch

; &e0e2 referenced 1 time by &e086
.ce0e2
    lda #1                                                            ; e0e2: a9 01       ..
    bit adlc_a_cr2                                                    ; e0e4: 2c 01 c8    ,..
    beq ce13c                                                         ; e0e7: f0 53       .S
    lda adlc_a_tx                                                     ; e0e9: ad 02 c8    ...
    sta l023c                                                         ; e0ec: 8d 3c 02    .<.
    jsr wait_adlc_a_irq                                               ; e0ef: 20 e4 e3     ..
    bit adlc_a_cr2                                                    ; e0f2: 2c 01 c8    ,..
    bpl ce13c                                                         ; e0f5: 10 45       .E
    ldy adlc_a_tx                                                     ; e0f7: ac 02 c8    ...
    beq ce13f                                                         ; e0fa: f0 43       .C
    lda net_a_map,y                                                   ; e0fc: b9 5a 02    .Z.
    beq ce13f                                                         ; e0ff: f0 3e       .>
    sty l023d                                                         ; e101: 8c 3d 02    .=.
    ldy #2                                                            ; e104: a0 02       ..
; &e106 referenced 1 time by &e11e
.loop_ce106
    jsr wait_adlc_a_irq                                               ; e106: 20 e4 e3     ..
    bit adlc_a_cr2                                                    ; e109: 2c 01 c8    ,..
    bpl ce120                                                         ; e10c: 10 12       ..
    lda adlc_a_tx                                                     ; e10e: ad 02 c8    ...
    sta l023c,y                                                       ; e111: 99 3c 02    .<.
    iny                                                               ; e114: c8          .
    lda adlc_a_tx                                                     ; e115: ad 02 c8    ...
    sta l023c,y                                                       ; e118: 99 3c 02    .<.
    iny                                                               ; e11b: c8          .
    cpy #&14                                                          ; e11c: c0 14       ..
    bcc loop_ce106                                                    ; e11e: 90 e6       ..
; &e120 referenced 1 time by &e10c
.ce120
    lda #0                                                            ; e120: a9 00       ..
    sta adlc_a_cr1                                                    ; e122: 8d 00 c8    ...
    lda #&84                                                          ; e125: a9 84       ..
    sta adlc_a_cr2                                                    ; e127: 8d 01 c8    ...
    lda #2                                                            ; e12a: a9 02       ..
    bit adlc_a_cr2                                                    ; e12c: 2c 01 c8    ,..
    beq ce13c                                                         ; e12f: f0 0b       ..
    bpl ce14a                                                         ; e131: 10 17       ..
    lda adlc_a_tx                                                     ; e133: ad 02 c8    ...
    sta l023c,y                                                       ; e136: 99 3c 02    .<.
    iny                                                               ; e139: c8          .
    bne ce14a                                                         ; e13a: d0 0e       ..
; &e13c referenced 4 times by &e0e7, &e0f5, &e12f, &e14f
.ce13c
    jmp ce051                                                         ; e13c: 4c 51 e0    LQ.

; &e13f referenced 2 times by &e0fa, &e0ff
.ce13f
    lda #&a2                                                          ; e13f: a9 a2       ..
    sta adlc_a_cr1                                                    ; e141: 8d 00 c8    ...
    jmp ce079                                                         ; e144: 4c 79 e0    Ly.

; &e147 referenced 2 times by &e171, &e180
.ce147
    jmp ce208                                                         ; e147: 4c 08 e2    L..

; &e14a referenced 2 times by &e131, &e13a
.ce14a
    sty l0228                                                         ; e14a: 8c 28 02    .(.
    cpy #6                                                            ; e14d: c0 06       ..
    bcc ce13c                                                         ; e14f: 90 eb       ..
    lda l023f                                                         ; e151: ad 3f 02    .?.
    bne ce15c                                                         ; e154: d0 06       ..
    lda station_id_a                                                  ; e156: ad 00 c0    ...
    sta l023f                                                         ; e159: 8d 3f 02    .?.
; &e15c referenced 1 time by &e154
.ce15c
    lda station_id_b                                                  ; e15c: ad 00 d0    ...
    cmp l023d                                                         ; e15f: cd 3d 02    .=.
    bne ce169                                                         ; e162: d0 05       ..
    lda #0                                                            ; e164: a9 00       ..
    sta l023d                                                         ; e166: 8d 3d 02    .=.
; &e169 referenced 1 time by &e162
.ce169
    lda l023c                                                         ; e169: ad 3c 02    .<.
    and l023d                                                         ; e16c: 2d 3d 02    -=.
    cmp #&ff                                                          ; e16f: c9 ff       ..
    bne ce147                                                         ; e171: d0 d4       ..
    jsr adlc_a_listen                                                 ; e173: 20 ff e3     ..
    lda #&c2                                                          ; e176: a9 c2       ..
    sta adlc_a_cr1                                                    ; e178: 8d 00 c8    ...
    lda l0241                                                         ; e17b: ad 41 02    .A.
    cmp #&9c                                                          ; e17e: c9 9c       ..
    bne ce147                                                         ; e180: d0 c5       ..
    lda l0240                                                         ; e182: ad 40 02    .@.
    cmp #&81                                                          ; e185: c9 81       ..
    beq ce1ee                                                         ; e187: f0 65       .e
    cmp #&80                                                          ; e189: c9 80       ..
    beq ce1d6                                                         ; e18b: f0 49       .I
    cmp #&82                                                          ; e18d: c9 82       ..
    beq ce19d                                                         ; e18f: f0 0c       ..
    cmp #&83                                                          ; e191: c9 83       ..
    bne ce208                                                         ; e193: d0 73       .s
    ldy l0249                                                         ; e195: ac 49 02    .I.
    lda net_a_map,y                                                   ; e198: b9 5a 02    .Z.
    beq ce1d3                                                         ; e19b: f0 36       .6
; &e19d referenced 1 time by &e18f
.ce19d
    jsr adlc_a_listen                                                 ; e19d: 20 ff e3     ..
    jsr sub_ce48d                                                     ; e1a0: 20 8d e4     ..
    lda station_id_b                                                  ; e1a3: ad 00 d0    ...
    sta tx_src_net                                                    ; e1a6: 8d 5d 04    .].
    sta l0214                                                         ; e1a9: 8d 14 02    ...
    jsr sub_ce448                                                     ; e1ac: 20 48 e4     H.
    jsr sub_ce6dc                                                     ; e1af: 20 dc e6     ..
    jsr sub_ce517                                                     ; e1b2: 20 17 e5     ..
    jsr sub_ce56e                                                     ; e1b5: 20 6e e5     n.
    jsr sub_ce48d                                                     ; e1b8: 20 8d e4     ..
    lda station_id_b                                                  ; e1bb: ad 00 d0    ...
    sta tx_src_net                                                    ; e1be: 8d 5d 04    .].
    lda station_id_a                                                  ; e1c1: ad 00 c0    ...
    sta tx_ctrl                                                       ; e1c4: 8d 5e 04    .^.
    lda l0249                                                         ; e1c7: ad 49 02    .I.
    sta tx_port                                                       ; e1ca: 8d 5f 04    ._.
    jsr sub_ce517                                                     ; e1cd: 20 17 e5     ..
    jsr sub_ce56e                                                     ; e1d0: 20 6e e5     n.
; &e1d3 referenced 1 time by &e19b
.ce1d3
    jmp ce051                                                         ; e1d3: 4c 51 e0    LQ.

; &e1d6 referenced 1 time by &e18b
.ce1d6
    jsr init_station_maps                                             ; e1d6: 20 24 e4     $.
    lda station_id_b                                                  ; e1d9: ad 00 d0    ...
    sta l022b                                                         ; e1dc: 8d 2b 02    .+.
    lda #0                                                            ; e1df: a9 00       ..
    sta l022a                                                         ; e1e1: 8d 2a 02    .*.
    lda #&0a                                                          ; e1e4: a9 0a       ..
    sta l022c                                                         ; e1e6: 8d 2c 02    .,.
    lda #&40 ; '@'                                                    ; e1e9: a9 40       .@
    sta l0229                                                         ; e1eb: 8d 29 02    .).
; &e1ee referenced 1 time by &e187
.ce1ee
    ldy #6                                                            ; e1ee: a0 06       ..
; &e1f0 referenced 1 time by &e1fd
.loop_ce1f0
    lda l023c,y                                                       ; e1f0: b9 3c 02    .<.
    tax                                                               ; e1f3: aa          .
    lda #&ff                                                          ; e1f4: a9 ff       ..
    sta net_b_map,x                                                   ; e1f6: 9d 5a 03    .Z.
    iny                                                               ; e1f9: c8          .
    cpy l0228                                                         ; e1fa: cc 28 02    .(.
    bne loop_ce1f0                                                    ; e1fd: d0 f1       ..
    lda station_id_a                                                  ; e1ff: ad 00 c0    ...
    sta l023c,y                                                       ; e202: 99 3c 02    .<.
    inc l0228                                                         ; e205: ee 28 02    .(.
; &e208 referenced 2 times by &e147, &e193
.ce208
    lda l0228                                                         ; e208: ad 28 02    .(.
    tax                                                               ; e20b: aa          .
    and #&fe                                                          ; e20c: 29 fe       ).
    sta l0228                                                         ; e20e: 8d 28 02    .(.
    jsr sub_ce690                                                     ; e211: 20 90 e6     ..
    ldy #0                                                            ; e214: a0 00       ..
; &e216 referenced 1 time by &e22f
.loop_ce216
    jsr wait_adlc_b_irq                                               ; e216: 20 ea e3     ..
    bit adlc_b_cr1                                                    ; e219: 2c 00 d8    ,..
    bvc ce260                                                         ; e21c: 50 42       PB
    lda l023c,y                                                       ; e21e: b9 3c 02    .<.
    sta adlc_b_tx                                                     ; e221: 8d 02 d8    ...
    iny                                                               ; e224: c8          .
    lda l023c,y                                                       ; e225: b9 3c 02    .<.
    sta adlc_b_tx                                                     ; e228: 8d 02 d8    ...
    iny                                                               ; e22b: c8          .
    cpy l0228                                                         ; e22c: cc 28 02    .(.
    bcc loop_ce216                                                    ; e22f: 90 e5       ..
    txa                                                               ; e231: 8a          .
    ror a                                                             ; e232: 6a          j
    bcc ce23e                                                         ; e233: 90 09       ..
    jsr wait_adlc_b_irq                                               ; e235: 20 ea e3     ..
    lda l023c,y                                                       ; e238: b9 3c 02    .<.
    sta adlc_b_tx                                                     ; e23b: 8d 02 d8    ...
; &e23e referenced 1 time by &e233
.ce23e
    lda #&3f ; '?'                                                    ; e23e: a9 3f       .?
    sta adlc_b_cr2                                                    ; e240: 8d 01 d8    ...
    jsr wait_adlc_b_irq                                               ; e243: 20 ea e3     ..
    lda #&5a ; 'Z'                                                    ; e246: a9 5a       .Z
    sta mem_ptr_lo                                                    ; e248: 85 80       ..
    lda #4                                                            ; e24a: a9 04       ..
    sta mem_ptr_hi                                                    ; e24c: 85 81       ..
    jsr sub_ce5ff                                                     ; e24e: 20 ff e5     ..
    jsr sub_ce517                                                     ; e251: 20 17 e5     ..
    jsr sub_ce56e                                                     ; e254: 20 6e e5     n.
    jsr sub_ce4c0                                                     ; e257: 20 c0 e4     ..
    jsr sub_ce5ff                                                     ; e25a: 20 ff e5     ..
    jsr sub_ce517                                                     ; e25d: 20 17 e5     ..
; &e260 referenced 1 time by &e21c
.ce260
    jmp ce051                                                         ; e260: 4c 51 e0    LQ.

; &e263 referenced 1 time by &e07e
.ce263
    lda #1                                                            ; e263: a9 01       ..
    bit adlc_b_cr2                                                    ; e265: 2c 01 d8    ,..
    beq ce2bd                                                         ; e268: f0 53       .S
    lda adlc_b_tx                                                     ; e26a: ad 02 d8    ...
    sta l023c                                                         ; e26d: 8d 3c 02    .<.
    jsr wait_adlc_b_irq                                               ; e270: 20 ea e3     ..
    bit adlc_b_cr2                                                    ; e273: 2c 01 d8    ,..
    bpl ce2bd                                                         ; e276: 10 45       .E
    ldy adlc_b_tx                                                     ; e278: ac 02 d8    ...
    beq ce2c0                                                         ; e27b: f0 43       .C
    lda net_b_map,y                                                   ; e27d: b9 5a 03    .Z.
    beq ce2c0                                                         ; e280: f0 3e       .>
    sty l023d                                                         ; e282: 8c 3d 02    .=.
    ldy #2                                                            ; e285: a0 02       ..
; &e287 referenced 1 time by &e29f
.loop_ce287
    jsr wait_adlc_b_irq                                               ; e287: 20 ea e3     ..
    bit adlc_b_cr2                                                    ; e28a: 2c 01 d8    ,..
    bpl ce2a1                                                         ; e28d: 10 12       ..
    lda adlc_b_tx                                                     ; e28f: ad 02 d8    ...
    sta l023c,y                                                       ; e292: 99 3c 02    .<.
    iny                                                               ; e295: c8          .
    lda adlc_b_tx                                                     ; e296: ad 02 d8    ...
    sta l023c,y                                                       ; e299: 99 3c 02    .<.
    iny                                                               ; e29c: c8          .
    cpy #&14                                                          ; e29d: c0 14       ..
    bcc loop_ce287                                                    ; e29f: 90 e6       ..
; &e2a1 referenced 1 time by &e28d
.ce2a1
    lda #0                                                            ; e2a1: a9 00       ..
    sta adlc_b_cr1                                                    ; e2a3: 8d 00 d8    ...
    lda #&84                                                          ; e2a6: a9 84       ..
    sta adlc_b_cr2                                                    ; e2a8: 8d 01 d8    ...
    lda #2                                                            ; e2ab: a9 02       ..
    bit adlc_b_cr2                                                    ; e2ad: 2c 01 d8    ,..
    beq ce2bd                                                         ; e2b0: f0 0b       ..
    bpl ce2cb                                                         ; e2b2: 10 17       ..
    lda adlc_b_tx                                                     ; e2b4: ad 02 d8    ...
    sta l023c,y                                                       ; e2b7: 99 3c 02    .<.
    iny                                                               ; e2ba: c8          .
    bne ce2cb                                                         ; e2bb: d0 0e       ..
; &e2bd referenced 4 times by &e268, &e276, &e2b0, &e2d0
.ce2bd
    jmp ce051                                                         ; e2bd: 4c 51 e0    LQ.

; &e2c0 referenced 2 times by &e27b, &e280
.ce2c0
    lda #&a2                                                          ; e2c0: a9 a2       ..
    sta adlc_b_cr1                                                    ; e2c2: 8d 00 d8    ...
    jmp ce079                                                         ; e2c5: 4c 79 e0    Ly.

; &e2c8 referenced 2 times by &e2f2, &e301
.ce2c8
    jmp ce389                                                         ; e2c8: 4c 89 e3    L..

; &e2cb referenced 2 times by &e2b2, &e2bb
.ce2cb
    sty l0228                                                         ; e2cb: 8c 28 02    .(.
    cpy #6                                                            ; e2ce: c0 06       ..
    bcc ce2bd                                                         ; e2d0: 90 eb       ..
    lda l023f                                                         ; e2d2: ad 3f 02    .?.
    bne ce2dd                                                         ; e2d5: d0 06       ..
    lda station_id_b                                                  ; e2d7: ad 00 d0    ...
    sta l023f                                                         ; e2da: 8d 3f 02    .?.
; &e2dd referenced 1 time by &e2d5
.ce2dd
    lda station_id_a                                                  ; e2dd: ad 00 c0    ...
    cmp l023d                                                         ; e2e0: cd 3d 02    .=.
    bne ce2ea                                                         ; e2e3: d0 05       ..
    lda #0                                                            ; e2e5: a9 00       ..
    sta l023d                                                         ; e2e7: 8d 3d 02    .=.
; &e2ea referenced 1 time by &e2e3
.ce2ea
    lda l023c                                                         ; e2ea: ad 3c 02    .<.
    and l023d                                                         ; e2ed: 2d 3d 02    -=.
    cmp #&ff                                                          ; e2f0: c9 ff       ..
    bne ce2c8                                                         ; e2f2: d0 d4       ..
    jsr adlc_b_listen                                                 ; e2f4: 20 19 e4     ..
    lda #&c2                                                          ; e2f7: a9 c2       ..
    sta adlc_b_cr1                                                    ; e2f9: 8d 00 d8    ...
    lda l0241                                                         ; e2fc: ad 41 02    .A.
    cmp #&9c                                                          ; e2ff: c9 9c       ..
    bne ce2c8                                                         ; e301: d0 c5       ..
    lda l0240                                                         ; e303: ad 40 02    .@.
    cmp #&81                                                          ; e306: c9 81       ..
    beq ce36f                                                         ; e308: f0 65       .e
    cmp #&80                                                          ; e30a: c9 80       ..
    beq ce357                                                         ; e30c: f0 49       .I
    cmp #&82                                                          ; e30e: c9 82       ..
    beq ce31e                                                         ; e310: f0 0c       ..
    cmp #&83                                                          ; e312: c9 83       ..
    bne ce389                                                         ; e314: d0 73       .s
    ldy l0249                                                         ; e316: ac 49 02    .I.
    lda net_b_map,y                                                   ; e319: b9 5a 03    .Z.
    beq ce354                                                         ; e31c: f0 36       .6
; &e31e referenced 1 time by &e310
.ce31e
    jsr adlc_b_listen                                                 ; e31e: 20 19 e4     ..
    jsr sub_ce48d                                                     ; e321: 20 8d e4     ..
    lda station_id_a                                                  ; e324: ad 00 c0    ...
    sta tx_src_net                                                    ; e327: 8d 5d 04    .].
    sta l0214                                                         ; e32a: 8d 14 02    ...
    jsr sub_ce448                                                     ; e32d: 20 48 e4     H.
    jsr sub_ce690                                                     ; e330: 20 90 e6     ..
    jsr sub_ce4c0                                                     ; e333: 20 c0 e4     ..
    jsr sub_ce5ff                                                     ; e336: 20 ff e5     ..
    jsr sub_ce48d                                                     ; e339: 20 8d e4     ..
    lda station_id_a                                                  ; e33c: ad 00 c0    ...
    sta tx_src_net                                                    ; e33f: 8d 5d 04    .].
    lda station_id_b                                                  ; e342: ad 00 d0    ...
    sta tx_ctrl                                                       ; e345: 8d 5e 04    .^.
    lda l0249                                                         ; e348: ad 49 02    .I.
    sta tx_port                                                       ; e34b: 8d 5f 04    ._.
    jsr sub_ce4c0                                                     ; e34e: 20 c0 e4     ..
    jsr sub_ce5ff                                                     ; e351: 20 ff e5     ..
; &e354 referenced 1 time by &e31c
.ce354
    jmp ce051                                                         ; e354: 4c 51 e0    LQ.

; &e357 referenced 1 time by &e30c
.ce357
    jsr init_station_maps                                             ; e357: 20 24 e4     $.
    lda station_id_a                                                  ; e35a: ad 00 c0    ...
    sta l022b                                                         ; e35d: 8d 2b 02    .+.
    lda #0                                                            ; e360: a9 00       ..
    sta l022a                                                         ; e362: 8d 2a 02    .*.
    lda #&0a                                                          ; e365: a9 0a       ..
    sta l022c                                                         ; e367: 8d 2c 02    .,.
    lda #&80                                                          ; e36a: a9 80       ..
    sta l0229                                                         ; e36c: 8d 29 02    .).
; &e36f referenced 1 time by &e308
.ce36f
    ldy #6                                                            ; e36f: a0 06       ..
; &e371 referenced 1 time by &e37e
.loop_ce371
    lda l023c,y                                                       ; e371: b9 3c 02    .<.
    tax                                                               ; e374: aa          .
    lda #&ff                                                          ; e375: a9 ff       ..
    sta net_a_map,x                                                   ; e377: 9d 5a 02    .Z.
    iny                                                               ; e37a: c8          .
    cpy l0228                                                         ; e37b: cc 28 02    .(.
    bne loop_ce371                                                    ; e37e: d0 f1       ..
    lda station_id_b                                                  ; e380: ad 00 d0    ...
    sta l023c,y                                                       ; e383: 99 3c 02    .<.
    inc l0228                                                         ; e386: ee 28 02    .(.
; &e389 referenced 2 times by &e2c8, &e314
.ce389
    lda l0228                                                         ; e389: ad 28 02    .(.
    tax                                                               ; e38c: aa          .
    and #&fe                                                          ; e38d: 29 fe       ).
    sta l0228                                                         ; e38f: 8d 28 02    .(.
    jsr sub_ce6dc                                                     ; e392: 20 dc e6     ..
    ldy #0                                                            ; e395: a0 00       ..
; &e397 referenced 1 time by &e3b0
.loop_ce397
    jsr wait_adlc_a_irq                                               ; e397: 20 e4 e3     ..
    bit adlc_a_cr1                                                    ; e39a: 2c 00 c8    ,..
    bvc ce3e1                                                         ; e39d: 50 42       PB
    lda l023c,y                                                       ; e39f: b9 3c 02    .<.
    sta adlc_a_tx                                                     ; e3a2: 8d 02 c8    ...
    iny                                                               ; e3a5: c8          .
    lda l023c,y                                                       ; e3a6: b9 3c 02    .<.
    sta adlc_a_tx                                                     ; e3a9: 8d 02 c8    ...
    iny                                                               ; e3ac: c8          .
    cpy l0228                                                         ; e3ad: cc 28 02    .(.
    bcc loop_ce397                                                    ; e3b0: 90 e5       ..
    txa                                                               ; e3b2: 8a          .
    ror a                                                             ; e3b3: 6a          j
    bcc ce3bf                                                         ; e3b4: 90 09       ..
    jsr wait_adlc_a_irq                                               ; e3b6: 20 e4 e3     ..
    lda l023c,y                                                       ; e3b9: b9 3c 02    .<.
    sta adlc_a_tx                                                     ; e3bc: 8d 02 c8    ...
; &e3bf referenced 1 time by &e3b4
.ce3bf
    lda #&3f ; '?'                                                    ; e3bf: a9 3f       .?
    sta adlc_a_cr2                                                    ; e3c1: 8d 01 c8    ...
    jsr wait_adlc_a_irq                                               ; e3c4: 20 e4 e3     ..
    lda #&5a ; 'Z'                                                    ; e3c7: a9 5a       .Z
    sta mem_ptr_lo                                                    ; e3c9: 85 80       ..
    lda #4                                                            ; e3cb: a9 04       ..
    sta mem_ptr_hi                                                    ; e3cd: 85 81       ..
    jsr sub_ce56e                                                     ; e3cf: 20 6e e5     n.
    jsr sub_ce4c0                                                     ; e3d2: 20 c0 e4     ..
    jsr sub_ce5ff                                                     ; e3d5: 20 ff e5     ..
    jsr sub_ce517                                                     ; e3d8: 20 17 e5     ..
    jsr sub_ce56e                                                     ; e3db: 20 6e e5     n.
    jsr sub_ce4c0                                                     ; e3de: 20 c0 e4     ..
; &e3e1 referenced 1 time by &e39d
.ce3e1
    jmp ce051                                                         ; e3e1: 4c 51 e0    LQ.

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
; CR3=&00: normal, NRZ, no loop-back, no DTR
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
; Zeroes net_a_map and net_b_map (256 bytes each), then writes &FF
; to three slots:
; 
;   net_b_map[station_id_a]    — the bridge's port-A station
;   net_a_map[station_id_b]    — the bridge's port-B station
;   net_a_map[255]             — broadcast slot
;   net_b_map[255]             — broadcast slot
; 
; Called from the reset handler and also re-invoked at &E1D6 and
; &E357 — probably after network topology changes or administrative
; re-init. The &FF-marked slots prevent the bridge from being
; confused by traffic to/from its own station IDs or broadcasts
; during routing decisions.
; Y = 0, A = 0: set up to clear both tables
; &e424 referenced 3 times by &e002, &e1d6, &e357
.init_station_maps
    ldy #0                                                            ; e424: a0 00       ..
    lda #0                                                            ; e426: a9 00       ..
; Zero net_a_map[Y]
; &e428 referenced 1 time by &e42f
.loop_ce428
    sta net_a_map,y                                                   ; e428: 99 5a 02    .Z.
; Zero net_b_map[Y]
    sta net_b_map,y                                                   ; e42b: 99 5a 03    .Z.
    iny                                                               ; e42e: c8          .
; Loop over all 256 slots (Y wraps back to 0)
    bne loop_ce428                                                    ; e42f: d0 f7       ..
; Marker value &FF for the special slots below
    lda #&ff                                                          ; e431: a9 ff       ..
; Port A bridge-station slot -> mark in net_b_map
    ldy station_id_a                                                  ; e433: ac 00 c0    ...
    sta net_b_map,y                                                   ; e436: 99 5a 03    .Z.
; Port B bridge-station slot -> mark in net_a_map
    ldy station_id_b                                                  ; e439: ac 00 d0    ...
    sta net_a_map,y                                                   ; e43c: 99 5a 02    .Z.
; Broadcast slot (255) in both maps
    ldy #&ff                                                          ; e43f: a0 ff       ..
    sta net_a_map,y                                                   ; e441: 99 5a 02    .Z.
    sta net_b_map,y                                                   ; e444: 99 5a 03    .Z.
    rts                                                               ; e447: 60          `

; &e448 referenced 2 times by &e1ac, &e32d
.sub_ce448
    ldy #&40 ; '@'                                                    ; e448: a0 40       .@
; &e44a referenced 1 time by &e44b
.loop_ce44a
    dey                                                               ; e44a: 88          .
    bne loop_ce44a                                                    ; e44b: d0 fd       ..
; &e44d referenced 1 time by &e455
.loop_ce44d
    ldy #&14                                                          ; e44d: a0 14       ..
; &e44f referenced 1 time by &e450
.loop_ce44f
    dey                                                               ; e44f: 88          .
    bne loop_ce44f                                                    ; e450: d0 fd       ..
    dec l0214                                                         ; e452: ce 14 02    ...
    bne loop_ce44d                                                    ; e455: d0 f6       ..
    rts                                                               ; e457: 60          `

; ***************************************************************************************
; Populate outbound frame with a side-B bridge announcement
; 
; Populates the outbound frame control block at &045A-&0460 with
; an all-broadcast bridge announcement aimed at Econet side B:
; 
;   tx_dst_stn = &FF                    broadcast station
;   tx_dst_net = &FF                    broadcast network
;   tx_src_stn = &18                    provisional bridge id (TBD)
;   tx_src_net = &18                    provisional bridge id (TBD)
;   tx_ctrl    = &80                    scout control byte
;   tx_port    = &9C                    bridge-protocol port
;   tx_data0   = station_id_b           bridge's station on side B
; 
; Also writes &06 to &0200 and &04 to &0201 (purpose provisional:
; probable length/selector fields in a separate transmit-command
; block), loads X=1 (likely side selector: 0 = side A, 1 = side B),
; and points mem_ptr at the frame block (&045A).
; 
; Called from the reset handler at &E038 and again from &E098. A
; structurally identical cousin builder lives at sub_ce48d (&E48D)
; and is called from four sites; it populates the same fields with
; values drawn from RAM variables at &023E and &0248 rather than
; baked-in constants.
; dst = &FFFF: broadcast station + network
; &e458 referenced 2 times by &e038, &e098
.build_announce_b
    lda #&ff                                                          ; e458: a9 ff       ..
    sta tx_dst_stn                                                    ; e45a: 8d 5a 04    .Z.
    sta tx_dst_net                                                    ; e45d: 8d 5b 04    .[.
; src = &1818: provisional bridge self-id
    lda #&18                                                          ; e460: a9 18       ..
    sta tx_src_stn                                                    ; e462: 8d 5c 04    .\.
    sta tx_src_net                                                    ; e465: 8d 5d 04    .].
; port = &9C (bridge-protocol port)
    lda #&9c                                                          ; e468: a9 9c       ..
    sta tx_port                                                       ; e46a: 8d 5f 04    ._.
; ctrl = &80 (scout)
    lda #&80                                                          ; e46d: a9 80       ..
    sta tx_ctrl                                                       ; e46f: 8d 5e 04    .^.
; Payload byte 0: bridge's station id on side B
    lda station_id_b                                                  ; e472: ad 00 d0    ...
    sta tx_data0                                                      ; e475: 8d 60 04    .`.
; X = 1: probable side selector (B)
    ldx #1                                                            ; e478: a2 01       ..
; tx command block: len=&06, ?=&04 (provisional)
    lda #6                                                            ; e47a: a9 06       ..
    sta l0200                                                         ; e47c: 8d 00 02    ...
    lda #4                                                            ; e47f: a9 04       ..
    sta l0201                                                         ; e481: 8d 01 02    ...
; mem_ptr = &045A (start of frame block)
    lda #&5a ; 'Z'                                                    ; e484: a9 5a       .Z
    sta mem_ptr_lo                                                    ; e486: 85 80       ..
    lda #4                                                            ; e488: a9 04       ..
    sta mem_ptr_hi                                                    ; e48a: 85 81       ..
    rts                                                               ; e48c: 60          `

; &e48d referenced 4 times by &e1a0, &e1b8, &e321, &e339
.sub_ce48d
    lda l023e                                                         ; e48d: ad 3e 02    .>.
    sta tx_dst_stn                                                    ; e490: 8d 5a 04    .Z.
    lda #0                                                            ; e493: a9 00       ..
    sta tx_dst_net                                                    ; e495: 8d 5b 04    .[.
    lda #0                                                            ; e498: a9 00       ..
    sta tx_src_stn                                                    ; e49a: 8d 5c 04    .\.
    sta tx_src_net                                                    ; e49d: 8d 5d 04    .].
    lda #&80                                                          ; e4a0: a9 80       ..
    sta tx_ctrl                                                       ; e4a2: 8d 5e 04    .^.
    lda l0248                                                         ; e4a5: ad 48 02    .H.
    sta tx_port                                                       ; e4a8: 8d 5f 04    ._.
    ldx #0                                                            ; e4ab: a2 00       ..
    lda #6                                                            ; e4ad: a9 06       ..
    sta l0200                                                         ; e4af: 8d 00 02    ...
    lda #4                                                            ; e4b2: a9 04       ..
    sta l0201                                                         ; e4b4: 8d 01 02    ...
    lda #&5a ; 'Z'                                                    ; e4b7: a9 5a       .Z
    sta mem_ptr_lo                                                    ; e4b9: 85 80       ..
    lda #4                                                            ; e4bb: a9 04       ..
    sta mem_ptr_hi                                                    ; e4bd: 85 81       ..
    rts                                                               ; e4bf: 60          `

; &e4c0 referenced 7 times by &e04e, &e0d8, &e257, &e333, &e34e, &e3d2, &e3de
.sub_ce4c0
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
    jmp ce051                                                         ; e4d6: 4c 51 e0    LQ.

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
    cpy l0200                                                         ; e4e9: cc 00 02    ...
    bne ce4cc                                                         ; e4ec: d0 de       ..
    lda mem_ptr_hi                                                    ; e4ee: a5 81       ..
    cmp l0201                                                         ; e4f0: cd 01 02    ...
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

; &e517 referenced 7 times by &e03e, &e0ad, &e1b2, &e1cd, &e251, &e25d, &e3d8
.sub_ce517
    lda #&e7                                                          ; e517: a9 e7       ..
    sta adlc_a_cr2                                                    ; e519: 8d 01 c8    ...
    lda #&44 ; 'D'                                                    ; e51c: a9 44       .D
    sta adlc_a_cr1                                                    ; e51e: 8d 00 c8    ...
    ldy #0                                                            ; e521: a0 00       ..
; &e523 referenced 2 times by &e543, &e54a
.ce523
    jsr wait_adlc_a_irq                                               ; e523: 20 e4 e3     ..
    bit adlc_a_cr1                                                    ; e526: 2c 00 c8    ,..
    bvs ce530                                                         ; e529: 70 05       p.
; &e52b referenced 1 time by &e556
.ce52b
    pla                                                               ; e52b: 68          h
    pla                                                               ; e52c: 68          h
    jmp ce051                                                         ; e52d: 4c 51 e0    LQ.

; &e530 referenced 1 time by &e529
.ce530
    lda (mem_ptr_lo),y                                                ; e530: b1 80       ..
    sta adlc_a_tx                                                     ; e532: 8d 02 c8    ...
    iny                                                               ; e535: c8          .
    lda (mem_ptr_lo),y                                                ; e536: b1 80       ..
    sta adlc_a_tx                                                     ; e538: 8d 02 c8    ...
    iny                                                               ; e53b: c8          .
    bne ce540                                                         ; e53c: d0 02       ..
    inc mem_ptr_hi                                                    ; e53e: e6 81       ..
; &e540 referenced 1 time by &e53c
.ce540
    cpy l0200                                                         ; e540: cc 00 02    ...
    bne ce523                                                         ; e543: d0 de       ..
    lda mem_ptr_hi                                                    ; e545: a5 81       ..
    cmp l0201                                                         ; e547: cd 01 02    ...
    bcc ce523                                                         ; e54a: 90 d7       ..
    txa                                                               ; e54c: 8a          .
    ror a                                                             ; e54d: 6a          j
    bcc ce55d                                                         ; e54e: 90 0d       ..
    jsr wait_adlc_a_irq                                               ; e550: 20 e4 e3     ..
    bit adlc_a_cr1                                                    ; e553: 2c 00 c8    ,..
    bvc ce52b                                                         ; e556: 50 d3       P.
    lda (mem_ptr_lo),y                                                ; e558: b1 80       ..
    sta adlc_a_tx                                                     ; e55a: 8d 02 c8    ...
; &e55d referenced 1 time by &e54e
.ce55d
    lda #&3f ; '?'                                                    ; e55d: a9 3f       .?
    sta adlc_a_cr2                                                    ; e55f: 8d 01 c8    ...
    jsr wait_adlc_a_irq                                               ; e562: 20 e4 e3     ..
    lda #&5a ; 'Z'                                                    ; e565: a9 5a       .Z
    sta mem_ptr_lo                                                    ; e567: 85 80       ..
    lda #4                                                            ; e569: a9 04       ..
    sta mem_ptr_hi                                                    ; e56b: 85 81       ..
    rts                                                               ; e56d: 60          `

; &e56e referenced 5 times by &e1b5, &e1d0, &e254, &e3cf, &e3db
.sub_ce56e
    lda #&82                                                          ; e56e: a9 82       ..
    sta adlc_a_cr1                                                    ; e570: 8d 00 c8    ...
    lda #1                                                            ; e573: a9 01       ..
    jsr wait_adlc_a_irq                                               ; e575: 20 e4 e3     ..
    bit adlc_a_cr2                                                    ; e578: 2c 01 c8    ,..
    beq ce5b1                                                         ; e57b: f0 34       .4
    lda adlc_a_tx                                                     ; e57d: ad 02 c8    ...
    sta tx_dst_stn                                                    ; e580: 8d 5a 04    .Z.
    jsr wait_adlc_a_irq                                               ; e583: 20 e4 e3     ..
    bit adlc_a_cr2                                                    ; e586: 2c 01 c8    ,..
    bpl ce5b1                                                         ; e589: 10 26       .&
    lda adlc_a_tx                                                     ; e58b: ad 02 c8    ...
    sta tx_dst_net                                                    ; e58e: 8d 5b 04    .[.
    ldy #2                                                            ; e591: a0 02       ..
; &e593 referenced 2 times by &e5a7, &e5af
.ce593
    jsr wait_adlc_a_irq                                               ; e593: 20 e4 e3     ..
    bit adlc_a_cr2                                                    ; e596: 2c 01 c8    ,..
    bpl ce5b6                                                         ; e599: 10 1b       ..
    lda adlc_a_tx                                                     ; e59b: ad 02 c8    ...
    sta (mem_ptr_lo),y                                                ; e59e: 91 80       ..
    iny                                                               ; e5a0: c8          .
    lda adlc_a_tx                                                     ; e5a1: ad 02 c8    ...
    sta (mem_ptr_lo),y                                                ; e5a4: 91 80       ..
    iny                                                               ; e5a6: c8          .
    bne ce593                                                         ; e5a7: d0 ea       ..
    inc mem_ptr_hi                                                    ; e5a9: e6 81       ..
    lda mem_ptr_hi                                                    ; e5ab: a5 81       ..
    cmp top_ram_page                                                  ; e5ad: c5 82       ..
    bcc ce593                                                         ; e5af: 90 e2       ..
; &e5b1 referenced 5 times by &e57b, &e589, &e5c5, &e5e4, &e5e9
.ce5b1
    pla                                                               ; e5b1: 68          h
    pla                                                               ; e5b2: 68          h
    jmp ce051                                                         ; e5b3: 4c 51 e0    LQ.

; &e5b6 referenced 1 time by &e599
.ce5b6
    lda #0                                                            ; e5b6: a9 00       ..
    sta adlc_a_cr1                                                    ; e5b8: 8d 00 c8    ...
    lda #&84                                                          ; e5bb: a9 84       ..
    sta adlc_a_cr2                                                    ; e5bd: 8d 01 c8    ...
    lda #2                                                            ; e5c0: a9 02       ..
    bit adlc_a_cr2                                                    ; e5c2: 2c 01 c8    ,..
    beq ce5b1                                                         ; e5c5: f0 ea       ..
    bpl ce5cf                                                         ; e5c7: 10 06       ..
    lda adlc_a_tx                                                     ; e5c9: ad 02 c8    ...
    sta (mem_ptr_lo),y                                                ; e5cc: 91 80       ..
    iny                                                               ; e5ce: c8          .
; &e5cf referenced 1 time by &e5c7
.ce5cf
    tya                                                               ; e5cf: 98          .
    tax                                                               ; e5d0: aa          .
    and #&fe                                                          ; e5d1: 29 fe       ).
    sta l0200                                                         ; e5d3: 8d 00 02    ...
    lda tx_src_net                                                    ; e5d6: ad 5d 04    .].
    bne ce5e1                                                         ; e5d9: d0 06       ..
    lda station_id_a                                                  ; e5db: ad 00 c0    ...
    sta tx_src_net                                                    ; e5de: 8d 5d 04    .].
; &e5e1 referenced 1 time by &e5d9
.ce5e1
    ldy tx_dst_net                                                    ; e5e1: ac 5b 04    .[.
    beq ce5b1                                                         ; e5e4: f0 cb       ..
    lda net_a_map,y                                                   ; e5e6: b9 5a 02    .Z.
    beq ce5b1                                                         ; e5e9: f0 c6       ..
    cpy station_id_b                                                  ; e5eb: cc 00 d0    ...
    bne ce5f5                                                         ; e5ee: d0 05       ..
    lda #0                                                            ; e5f0: a9 00       ..
    sta tx_dst_net                                                    ; e5f2: 8d 5b 04    .[.
; &e5f5 referenced 1 time by &e5ee
.ce5f5
    lda mem_ptr_hi                                                    ; e5f5: a5 81       ..
    sta l0201                                                         ; e5f7: 8d 01 02    ...
    lda #4                                                            ; e5fa: a9 04       ..
    sta mem_ptr_hi                                                    ; e5fc: 85 81       ..
    rts                                                               ; e5fe: 60          `

; &e5ff referenced 5 times by &e24e, &e25a, &e336, &e351, &e3d5
.sub_ce5ff
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
    jmp ce051                                                         ; e644: 4c 51 e0    LQ.

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
    sta l0200                                                         ; e664: 8d 00 02    ...
    lda tx_src_net                                                    ; e667: ad 5d 04    .].
    bne ce672                                                         ; e66a: d0 06       ..
    lda station_id_b                                                  ; e66c: ad 00 d0    ...
    sta tx_src_net                                                    ; e66f: 8d 5d 04    .].
; &e672 referenced 1 time by &e66a
.ce672
    ldy tx_dst_net                                                    ; e672: ac 5b 04    .[.
    beq ce642                                                         ; e675: f0 cb       ..
    lda net_b_map,y                                                   ; e677: b9 5a 03    .Z.
    beq ce642                                                         ; e67a: f0 c6       ..
    cpy station_id_a                                                  ; e67c: cc 00 c0    ...
    bne ce686                                                         ; e67f: d0 05       ..
    lda #0                                                            ; e681: a9 00       ..
    sta tx_dst_net                                                    ; e683: 8d 5b 04    .[.
; &e686 referenced 1 time by &e67f
.ce686
    lda mem_ptr_hi                                                    ; e686: a5 81       ..
    sta l0201                                                         ; e688: 8d 01 02    ...
    lda #4                                                            ; e68b: a9 04       ..
    sta mem_ptr_hi                                                    ; e68d: 85 81       ..
    rts                                                               ; e68f: 60          `

; &e690 referenced 4 times by &e04b, &e0d5, &e211, &e330
.sub_ce690
    lda #0                                                            ; e690: a9 00       ..
    sta l0214                                                         ; e692: 8d 14 02    ...
    sta l0215                                                         ; e695: 8d 15 02    ...
    lda #&fe                                                          ; e698: a9 fe       ..
    sta l0216                                                         ; e69a: 8d 16 02    ...
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
    inc l0214                                                         ; e6bf: ee 14 02    ...
    bne ce6a2                                                         ; e6c2: d0 de       ..
    inc l0215                                                         ; e6c4: ee 15 02    ...
    bne ce6a2                                                         ; e6c7: d0 d9       ..
    inc l0216                                                         ; e6c9: ee 16 02    ...
    bne ce6a2                                                         ; e6cc: d0 d4       ..
    pla                                                               ; e6ce: 68          h
    pla                                                               ; e6cf: 68          h
    jmp ce051                                                         ; e6d0: 4c 51 e0    LQ.

; &e6d3 referenced 1 time by &e6ac
.ce6d3
    sty adlc_b_cr2                                                    ; e6d3: 8c 01 d8    ...
    lda #&44 ; 'D'                                                    ; e6d6: a9 44       .D
    sta adlc_b_cr1                                                    ; e6d8: 8d 00 d8    ...
    rts                                                               ; e6db: 60          `

; &e6dc referenced 4 times by &e03b, &e0aa, &e1af, &e392
.sub_ce6dc
    lda #0                                                            ; e6dc: a9 00       ..
    sta l0214                                                         ; e6de: 8d 14 02    ...
    sta l0215                                                         ; e6e1: 8d 15 02    ...
    lda #&fe                                                          ; e6e4: a9 fe       ..
    sta l0216                                                         ; e6e6: 8d 16 02    ...
    lda adlc_a_cr2                                                    ; e6e9: ad 01 c8    ...
    ldy #&e7                                                          ; e6ec: a0 e7       ..
; &e6ee referenced 3 times by &e70e, &e713, &e718
.ce6ee
    lda #&67 ; 'g'                                                    ; e6ee: a9 67       .g
    sta adlc_a_cr2                                                    ; e6f0: 8d 01 c8    ...
    lda #4                                                            ; e6f3: a9 04       ..
    bit adlc_a_cr2                                                    ; e6f5: 2c 01 c8    ,..
    bne ce71f                                                         ; e6f8: d0 25       .%
    lda adlc_a_cr2                                                    ; e6fa: ad 01 c8    ...
    and #&81                                                          ; e6fd: 29 81       ).
    beq ce70b                                                         ; e6ff: f0 0a       ..
    lda #&c2                                                          ; e701: a9 c2       ..
    sta adlc_a_cr1                                                    ; e703: 8d 00 c8    ...
    lda #&82                                                          ; e706: a9 82       ..
    sta adlc_a_cr1                                                    ; e708: 8d 00 c8    ...
; &e70b referenced 1 time by &e6ff
.ce70b
    inc l0214                                                         ; e70b: ee 14 02    ...
    bne ce6ee                                                         ; e70e: d0 de       ..
    inc l0215                                                         ; e710: ee 15 02    ...
    bne ce6ee                                                         ; e713: d0 d9       ..
    inc l0216                                                         ; e715: ee 16 02    ...
    bne ce6ee                                                         ; e718: d0 d4       ..
    pla                                                               ; e71a: 68          h
    pla                                                               ; e71b: 68          h
    jmp ce051                                                         ; e71c: 4c 51 e0    LQ.

; &e71f referenced 1 time by &e6f8
.ce71f
    sty adlc_a_cr2                                                    ; e71f: 8c 01 c8    ...
    lda #&44 ; 'D'                                                    ; e722: a9 44       .D
    sta adlc_a_cr1                                                    ; e724: 8d 00 c8    ...
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
; Forcibly reset and re-init both ADLCs
; 
; Differs subtly from the normal adlc_*_full_reset sequences: CR2
; is programmed to &80 and back to &67, a pattern used when the
; previous chip state is unknown. Re-entered at &F26C after certain
; test paths need to reset the chips again.
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
; CR2=&80 (both): clear status, RTS=1 (forces idle)
    lda #&80                                                          ; f015: a9 80       ..
    sta adlc_a_cr2                                                    ; f017: 8d 01 c8    ...
    lda #&80                                                          ; f01a: a9 80       ..
    sta adlc_b_cr2                                                    ; f01c: 8d 01 d8    ...
; CR1=&82 (both): TX in reset, RX IRQ enabled
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
    beq cf070                                                         ; f069: f0 05       ..
; Fail code 2: ROM checksum
    lda #2                                                            ; f06b: a9 02       ..
    jmp self_test_fail                                                ; f06d: 4c c7 f2    L..

; &f070 referenced 1 time by &f069
.cf070
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
    beq cf0a0                                                         ; f09b: f0 03       ..             ; ALWAYS branch

; &f09d referenced 6 times by &f039, &f03d, &f041, &f086, &f090, &f0c9
.cf09d
    jmp cf28c                                                         ; f09d: 4c 8c f2    L..

; &f0a0 referenced 1 time by &f09b
.cf0a0
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
    beq cf10a                                                         ; f0fe: f0 0a       ..
; &f100 referenced 2 times by &f0f0, &f0f7
.cf100
    lda #4                                                            ; f100: a9 04       ..
    jmp self_test_fail                                                ; f102: 4c c7 f2    L..

; &f105 referenced 3 times by &f0db, &f0e2, &f0e9
.cf105
    lda #3                                                            ; f105: a9 03       ..
    jmp self_test_fail                                                ; f107: 4c c7 f2    L..

; &f10a referenced 1 time by &f0fe
.cf10a
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
    lda station_id_a                                                  ; f24c: ad 00 c0    ...
    cmp #1                                                            ; f24f: c9 01       ..
    beq cf258                                                         ; f251: f0 05       ..
    lda #7                                                            ; f253: a9 07       ..
    jmp self_test_fail                                                ; f255: 4c c7 f2    L..

; &f258 referenced 1 time by &f251
.cf258
    lda station_id_b                                                  ; f258: ad 00 d0    ...
    cmp #2                                                            ; f25b: c9 02       ..
    beq cf264                                                         ; f25d: f0 05       ..
    lda #8                                                            ; f25f: a9 08       ..
    jmp self_test_fail                                                ; f261: 4c c7 f2    L..

; &f264 referenced 1 time by &f25d
.cf264
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

; &f28c referenced 1 time by &f09d
.cf28c
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
; Self-test failure — signal error code via ADLC A
; 
; Common failure exit from all self-test stages. Called with the
; error code in A. Save two copies of the code in &00/&01 then
; toggle adlc_a_cr2 in a timed pattern that probably drives a
; visible indicator (status LED or loopback-cable signal) with a
; blink count corresponding to the error code.
; 
; Reached from 7 sites: ROM checksum (&F06D, code 2), and six
; other failure points at &F102, &F107, &F153, &F1F4, &F255,
; &F261 (codes still to be identified).
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
;     adlc_a_cr2:              39
;     adlc_b_cr2:              34
;     adlc_a_cr1:              32
;     adlc_b_cr1:              29
;     adlc_a_tx:               26
;     adlc_b_tx:               26
;     mem_ptr_hi:              23
;     mem_ptr_lo:              23
;     l023c:                   20
;     wait_adlc_a_irq:         19
;     wait_adlc_b_irq:         19
;     l0000:                   15
;     l0001:                   15
;     ce051:                   14
;     station_id_a:            13
;     cf151:                   12
;     cf1f2:                   12
;     l0228:                   12
;     station_id_b:            12
;     l0002:                   10
;     tx_src_net:              10
;     l023d:                    8
;     tx_dst_net:               8
;     l0214:                    7
;     net_a_map:                7
;     net_b_map:                7
;     pydis_start:              7
;     reset:                    7
;     self_test_fail:           7
;     sub_ce4c0:                7
;     sub_ce517:                7
;     cf09d:                    6
;     l0200:                    6
;     l0201:                    6
;     l0229:                    6
;     ce079:                    5
;     ce5b1:                    5
;     ce642:                    5
;     sub_ce56e:                5
;     sub_ce5ff:                5
;     tx_ctrl:                  5
;     ce13c:                    4
;     ce2bd:                    4
;     l0215:                    4
;     l0216:                    4
;     l022a:                    4
;     l022b:                    4
;     l022c:                    4
;     l023f:                    4
;     l0249:                    4
;     sub_ce48d:                4
;     sub_ce690:                4
;     sub_ce6dc:                4
;     tx_dst_stn:               4
;     tx_port:                  4
;     ce6a2:                    3
;     ce6ee:                    3
;     cf105:                    3
;     cf2fa:                    3
;     init_station_maps:        3
;     l0003:                    3
;     top_ram_page:             3
;     tx_data0:                 3
;     adlc_a_listen:            2
;     adlc_a_tx2:               2
;     adlc_b_listen:            2
;     adlc_b_tx2:               2
;     build_announce_b:         2
;     ce0c2:                    2
;     ce13f:                    2
;     ce147:                    2
;     ce14a:                    2
;     ce208:                    2
;     ce2c0:                    2
;     ce2c8:                    2
;     ce2cb:                    2
;     ce389:                    2
;     ce4cc:                    2
;     ce523:                    2
;     ce593:                    2
;     ce624:                    2
;     cf05b:                    2
;     cf07e:                    2
;     cf0ac:                    2
;     cf0c6:                    2
;     cf100:                    2
;     cf29a:                    2
;     cf2a9:                    2
;     cf2d0:                    2
;     cf2d9:                    2
;     cf2e8:                    2
;     l0240:                    2
;     l0241:                    2
;     sub_ce448:                2
;     tx_src_stn:               2
;     adlc_a_full_reset:        1
;     adlc_b_full_reset:        1
;     ce05d:                    1
;     ce073:                    1
;     ce081:                    1
;     ce089:                    1
;     ce0b5:                    1
;     ce0ca:                    1
;     ce0e2:                    1
;     ce120:                    1
;     ce15c:                    1
;     ce169:                    1
;     ce19d:                    1
;     ce1d3:                    1
;     ce1d6:                    1
;     ce1ee:                    1
;     ce23e:                    1
;     ce260:                    1
;     ce263:                    1
;     ce2a1:                    1
;     ce2dd:                    1
;     ce2ea:                    1
;     ce31e:                    1
;     ce354:                    1
;     ce357:                    1
;     ce36f:                    1
;     ce3bf:                    1
;     ce3e1:                    1
;     ce4d4:                    1
;     ce4d9:                    1
;     ce4e9:                    1
;     ce506:                    1
;     ce52b:                    1
;     ce530:                    1
;     ce540:                    1
;     ce55d:                    1
;     ce5b6:                    1
;     ce5cf:                    1
;     ce5e1:                    1
;     ce5f5:                    1
;     ce647:                    1
;     ce660:                    1
;     ce672:                    1
;     ce686:                    1
;     ce6bf:                    1
;     ce6d3:                    1
;     ce70b:                    1
;     ce71f:                    1
;     cf070:                    1
;     cf0a0:                    1
;     cf10a:                    1
;     cf156:                    1
;     cf15c:                    1
;     cf1f7:                    1
;     cf1fd:                    1
;     cf258:                    1
;     cf264:                    1
;     cf26f:                    1
;     cf28c:                    1
;     cf291:                    1
;     l023e:                    1
;     l0248:                    1
;     loop_ce106:               1
;     loop_ce1f0:               1
;     loop_ce216:               1
;     loop_ce287:               1
;     loop_ce371:               1
;     loop_ce397:               1
;     loop_ce428:               1
;     loop_ce44a:               1
;     loop_ce44d:               1
;     loop_ce44f:               1
;     loop_cf031:               1
;     loop_cf125:               1
;     loop_cf189:               1
;     loop_cf1c6:               1
;     loop_cf22a:               1
;     ram_test_done:            1
;     ram_test_loop:            1
;     self_test_reset_adlcs:    1
;     self_test_rom_checksum:   1
;     self_test_zp:             1

; Automatically generated labels:
;     ce051
;     ce05d
;     ce073
;     ce079
;     ce081
;     ce089
;     ce0b5
;     ce0c2
;     ce0ca
;     ce0e2
;     ce120
;     ce13c
;     ce13f
;     ce147
;     ce14a
;     ce15c
;     ce169
;     ce19d
;     ce1d3
;     ce1d6
;     ce1ee
;     ce208
;     ce23e
;     ce260
;     ce263
;     ce2a1
;     ce2bd
;     ce2c0
;     ce2c8
;     ce2cb
;     ce2dd
;     ce2ea
;     ce31e
;     ce354
;     ce357
;     ce36f
;     ce389
;     ce3bf
;     ce3e1
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
;     cf070
;     cf07e
;     cf09d
;     cf0a0
;     cf0ac
;     cf0c6
;     cf100
;     cf105
;     cf10a
;     cf151
;     cf156
;     cf15c
;     cf1f2
;     cf1f7
;     cf1fd
;     cf258
;     cf264
;     cf26f
;     cf28c
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
;     l0200
;     l0201
;     l0214
;     l0215
;     l0216
;     l0228
;     l0229
;     l022a
;     l022b
;     l022c
;     l023c
;     l023d
;     l023e
;     l023f
;     l0240
;     l0241
;     l0248
;     l0249
;     loop_ce106
;     loop_ce1f0
;     loop_ce216
;     loop_ce287
;     loop_ce371
;     loop_ce397
;     loop_ce428
;     loop_ce44a
;     loop_ce44d
;     loop_ce44f
;     loop_cf031
;     loop_cf125
;     loop_cf189
;     loop_cf1c6
;     loop_cf22a
;     sub_ce448
;     sub_ce48d
;     sub_ce4c0
;     sub_ce517
;     sub_ce56e
;     sub_ce5ff
;     sub_ce690
;     sub_ce6dc

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
