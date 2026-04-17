"""Disassembly driver for Acorn Econet Bridge version 1.

Configures py8dis to produce an annotated disassembly of the Econet
Bridge ROM.

Run via: uv run acorn-econet-bridge-disasm-tool disassemble 1

The bridge contains an 8 KB ROM mapped at &E000-&FFFF on its own
6502 processor. The hardware vectors are the last six bytes of the
ROM:

  &FFFA/B  NMI   vector
  &FFFC/D  RESET vector
  &FFFE/F  IRQ/BRK vector
"""

import json
import os
import sys
from pathlib import Path

from py8dis.commands import *

init(assembler_name="beebasm", lower_case=True)

_script_dirpath = Path(__file__).resolve().parent
_version_dirpath = _script_dirpath.parent
_rom_filepath = os.environ.get(
    "ACORN_ECONET_BRIDGE_ROM",
    str(_version_dirpath / "rom" / "econet-bridge-1.rom"),
)
_output_dirpath = Path(os.environ.get(
    "ACORN_ECONET_BRIDGE_OUTPUT",
    str(_version_dirpath / "output"),
))

load(0xE000, _rom_filepath, "6502")

# =====================================================================
# Hardware vectors
# =====================================================================
# The reset vector at &FFFC tells us where execution begins; the IRQ
# vector at &FFFE tells us where interrupts are serviced. These are
# the primary entry points into the ROM.

_reset_lo = get_u8_binary(0xFFFC)
_reset_hi = get_u8_binary(0xFFFD)
_reset_addr = _reset_lo | (_reset_hi << 8)

_irq_lo = get_u8_binary(0xFFFE)
_irq_hi = get_u8_binary(0xFFFF)
_irq_addr = _irq_lo | (_irq_hi << 8)

_nmi_lo = get_u8_binary(0xFFFA)
_nmi_hi = get_u8_binary(0xFFFB)
_nmi_addr = _nmi_lo | (_nmi_hi << 8)

entry(_reset_addr)
label(_reset_addr, "reset")

if 0xE000 <= _irq_addr <= 0xFFF9:
    entry(_irq_addr)
    label(_irq_addr, "self_test")
    # Hardware hint: the Bridge has a push-button pulling the 6502
    # ~IRQ line low (it's believed to be the only thing wired to that
    # pin). Pressing it enters the firmware's self-test routine — not
    # to be pressed while connected to a live network. So the IRQ
    # handler is effectively the self-test entry point, with BRK
    # sharing the same vector. The ADLC-generated interrupts that
    # drive Econet traffic are polled rather than vectored (see the
    # wait_adlc_*_irq helpers).

if 0xE000 <= _nmi_addr <= 0xFFF9:
    entry(_nmi_addr)
    label(_nmi_addr, "nmi_handler")

# Hardware vector data declarations
word(0xFFFA)
if 0xE000 <= _nmi_addr <= 0xFFF9:
    expr(0xFFFA, "nmi_handler")
comment(0xFFFA, "NMI vector", inline=True)

word(0xFFFC)
expr(0xFFFC, "reset")
comment(0xFFFC, "RESET vector", inline=True)

word(0xFFFE)
if 0xE000 <= _irq_addr <= 0xFFF9:
    expr(0xFFFE, "self_test")
comment(0xFFFE, "IRQ/BRK vector", inline=True)


# =====================================================================
# Hardware register map
# =====================================================================
# Outside the loaded ROM range, so declared with constant() rather
# than label(). Addresses confirmed by inspecting access patterns in
# the first-pass disassembly:
#
# - &C000 / &D000 are only ever read, consistent with the two
#   74LS244 buffers that expose the network-number selection links
#   (one per Econet port — each side of the Bridge has its own
#   network number, configured by jumpers/links on the board).
# - &C800-&C803 and &D800-&D803 are accessed with the exact pattern
#   of an MC6854 ADLC — CR1/SR1 at offset 0, CR2/SR2 at 1, TX/RX
#   FIFO at 2 and 3, with BIT reads of SR1 used to poll IRQ status
#   (the chip IRQ outputs are not wired to the 6502).
#
# Register semantics depend on the AC bit (Address Control) in CR1:
# when AC=0 the second-bank registers (CR2, SR2) are accessed at
# offsets 1; when AC=1 the fourth-bank registers (CR3, CR4) are
# accessed at offsets 0 and 1. The Acorn NFS disassembly uses the
# pre-AC names (cr1/cr2/tx/tx2) and we follow the same convention.

# Zero-page workspace used by the RAM test at reset. mem_ptr_lo and
# mem_ptr_hi form an indirect pointer scanned upward one page at a
# time; top_ram_page receives the last page that verified &AA/&55
# patterns and is used later by workspace init.
label(0x0080, "mem_ptr_lo")
label(0x0081, "mem_ptr_hi")
label(0x0082, "top_ram_page")

label(0xC000, "net_num_a")      # Read: Econet side A network number
label(0xD000, "net_num_b")      # Read: Econet side B network number
# Network numbers are 7-bit (range 1-127 per the Installation Guide);
# the top link on each jumper row is always made, so bit 7 is always
# zero. The Bridge has no station number of its own -- it sits on
# each Econet segment as a promiscuous receiver and broadcaster.

label(0xC800, "adlc_a_cr1")     # W: CR1 (or CR3 if AC=1). R: SR1
label(0xC801, "adlc_a_cr2")     # W: CR2 (or CR4 if AC=1). R: SR2
label(0xC802, "adlc_a_tx")      # W: TX FIFO (continue). R: RX FIFO
label(0xC803, "adlc_a_tx2")     # W: TX FIFO (last byte, ends frame)

label(0xD800, "adlc_b_cr1")
label(0xD801, "adlc_b_cr2")
label(0xD802, "adlc_b_tx")
label(0xD803, "adlc_b_tx2")


# =====================================================================
# ADLC polled-IRQ waits
# =====================================================================
# Each ADLC raises IRQ in SR1 bit 7 when attention is required. Since
# the 6502 ~IRQ line is used for the self-test button, the firmware
# polls SR1 for these helpers.

label(0xE3E4, "wait_adlc_a_irq")
subroutine(0xE3E4, "wait_adlc_a_irq", hook=None,
    title="Wait for ADLC A IRQ (polled)",
    description="""\
Spin reading SR1 of ADLC A until the IRQ bit (bit 7) is set. Called
from 19 sites where the code needs to wait for the ADLC to signal an
event (frame complete, RX data available, TX ready, etc.).

The Bridge does not route the ADLC ~IRQ output to the 6502 ~IRQ line
(that pin is used for the self-test push-button), so ADLC attention
is obtained by polling.""")

label(0xE3EA, "wait_adlc_b_irq")
subroutine(0xE3EA, "wait_adlc_b_irq", hook=None,
    title="Wait for ADLC B IRQ (polled)",
    description="""\
As wait_adlc_a_irq but for ADLC B.""")


# =====================================================================
# ADLC full reset + enter listen
# =====================================================================
# Each pair (full_reset -> listen) is called in sequence by the main
# reset handler at &E000 and from a few other paths that need to re-
# synchronise the chip. The two pairs are byte-for-byte mirrors —
# only the register addresses differ.
#
# Same ADLC initialisation sequence as Acorn NFS's adlc_full_reset +
# adlc_rx_listen (NFS 3.34 at &96DC / &96EB). This is the root of the
# shared-code region recorded in shared-code.json at &E3EF (matcher's
# alignment) / &E3F0 (actual subroutine start).

label(0xE3F0, "adlc_a_full_reset")
subroutine(0xE3F0, "adlc_a_full_reset", hook=None,
    title="ADLC A full reset, then enter RX listen",
    description="""\
Aborts all ADLC A activity and returns it to idle RX listen mode.
Falls through to adlc_a_listen. Called from the reset handler.""")

comment(0xE3F0, "CR1=&C1: reset TX+RX, AC=1 (enable CR3/CR4 access)")
comment(0xE3F5, "CR4=&1E: 8-bit RX, abort extend, NRZ")
comment(0xE3FA, "CR3=&00: normal, NRZ, no loop-back, no DTR")

label(0xE3FF, "adlc_a_listen")
subroutine(0xE3FF, "adlc_a_listen", hook=None,
    title="Enter ADLC A RX listen mode",
    description="""\
TX held in reset, RX active. IRQs are generated internally by the
chip but the ~IRQ output is not wired; see wait_adlc_a_irq.""")

comment(0xE3FF, "CR1=&82: TX in reset, RX interrupts enabled")
comment(0xE404, "CR2=&67: clear status, FC_TDRA, 2/1-byte, PSE")

label(0xE40A, "adlc_b_full_reset")
subroutine(0xE40A, "adlc_b_full_reset", hook=None,
    title="ADLC B full reset, then enter RX listen",
    description="""\
Byte-for-byte mirror of adlc_a_full_reset, targeting ADLC B's
register set at &D800-&D803. Falls through to adlc_b_listen.""")

comment(0xE40A, "CR1=&C1: reset TX+RX, AC=1 (enable CR3/CR4 access)")
comment(0xE40F, "CR4=&1E: 8-bit RX, abort extend, NRZ")
comment(0xE414, "CR3=&00: bit 7=0 -> LOC/DTR pin HIGH -> status LED OFF")

label(0xE419, "adlc_b_listen")
subroutine(0xE419, "adlc_b_listen", hook=None,
    title="Enter ADLC B RX listen mode",
    description="""\
Mirror of adlc_a_listen for ADLC B.""")

comment(0xE419, "CR1=&82: TX in reset, RX interrupts enabled")
comment(0xE41E, "CR2=&67: clear status, FC_TDRA, 2/1-byte, PSE")


# =====================================================================
# Inter-network routing tables
# =====================================================================
# Two 256-byte arrays indexed by destination
# NETWORK NUMBER (not station number). A non-zero entry means
# "this destination network is reachable from here".
#
#   reachable_via_b  at &025A  consulted by rx_frame_a.
#       Networks known to be accessible by forwarding an incoming
#       side-A frame out of side B. Initialised with net_num_b
#       (our own B-side network, directly reachable) and 255
#       (broadcast). Extended by bridge-announcement messages
#       received on side A.
#
#   reachable_via_a  at &035A  consulted by rx_frame_b.
#       Mirror.
#
# Naming note: the earlier provisional names `reachable_via_b` and
# `reachable_via_a` reflected which *handler* used them, not what they
# represented. Semantics resolved once the payload processing in
# rx_a_handle_80 revealed the map as a routing table.
label(0x025A, "reachable_via_b")
label(0x035A, "reachable_via_a")

# Multi-byte counter reused for different purposes by several
# routines. wait_adlc_a_idle (&E6DC) uses all three bytes as a
# 24-bit timeout; sub_ce448 (&E448) uses only the low byte as an
# 8-bit delay counter. Byte-aligned rather than semantic names so the
# shared use is explicit.
label(0x0214, "ctr24_lo")
label(0x0215, "ctr24_mid")
label(0x0216, "ctr24_hi")

# RX frame buffer. Inbound frames are drained from the ADLC's RX
# FIFO into this 20-byte region during the side-A and side-B
# handlers. The first six bytes are the Econet scout-frame header;
# bytes 6 onward are payload (max 14 bytes captured, enough for the
# Bridge-protocol message formats).
label(0x023C, "rx_dst_stn")   # byte 0: destination station
label(0x023D, "rx_dst_net")   # byte 1: destination network
label(0x023E, "rx_src_stn")   # byte 2: source station
label(0x023F, "rx_src_net")   # byte 3: source network
label(0x0240, "rx_ctrl")      # byte 4: control byte (bridge: &80-&83)
label(0x0241, "rx_port")      # byte 5: port (bridge-protocol = &9C)
# Payload bytes at &0242-&024F; named as they become understood.
# Byte 12 (&0248) holds a port number the querier wants the response
# on; byte 13 (&0249) holds a network number that ctrl=&83 queries
# ask about (the &83 path consults it against reachable_via_b, which
# is network-keyed).
label(0x0248, "rx_query_port") # byte 12: port for response frame
label(0x0249, "rx_query_net")  # byte 13: network number (ctrl=&83)
label(0x0228, "rx_len")       # bytes received (written at end of drain)

# Periodic re-announcement state, used by the main Bridge loop. The
# main loop polls both ADLCs for IRQs; in the idle path it tests
# announce_flag, and if set decrements announce_tmr_lo/hi. When the
# timer expires, it rebuilds and retransmits the bridge announce-
# ment, bumps announce_count, and clears announce_flag when the
# count runs out. Provisional names — refine as the full re-announce
# flow is analysed.
label(0x0229, "announce_flag")
label(0x022A, "announce_tmr_lo")
label(0x022B, "announce_tmr_hi")
label(0x022C, "announce_count")

# Outbound-frame control block at &045A-&0460. Populated by various
# "frame builder" subroutines, then consumed by transmit_frame_a
# (via mem_ptr at &80/&81 = &045A). Field names follow the Acorn
# Econet frame-header convention — provisional until the transmit
# routine is fully analysed.
label(0x045A, "tx_dst_stn")   # destination station (255 = broadcast)
label(0x045B, "tx_dst_net")   # destination network (255 = broadcast)
label(0x045C, "tx_src_stn")   # source station (provisional)
label(0x045D, "tx_src_net")   # source network (provisional)
label(0x045E, "tx_ctrl")      # control byte (scout flags)
label(0x045F, "tx_port")      # port number (protocol selector)
label(0x0460, "tx_data0")     # optional trailing payload byte

# Transmit end-pointer (16-bit, consumed by transmit_frame_a). The
# main TX loop sends byte pairs from mem_ptr upward and terminates
# once mem_ptr+Y reaches or passes (tx_end_hi:tx_end_lo). Builders
# for the "6-byte frame header" case write tx_end_lo=&06 and
# tx_end_hi=&04, corresponding to end address &0406 when combined
# with the buffer start at &045A (so the loop transmits up to Y=6,
# i.e. the 6 header bytes).
label(0x0200, "tx_end_lo")
label(0x0201, "tx_end_hi")


# =====================================================================
# Initialise per-station tables
# =====================================================================

label(0xE424, "init_reachable_nets")
subroutine(0xE424, "init_reachable_nets", hook=None,
    title="Clear the per-port station maps and mark bridge/broadcast",
    description="""\
Zeroes reachable_via_b and reachable_via_a (256 bytes each), then writes &FF
to three slots:

  reachable_via_a[net_num_a]    — the bridge's port-A station
  reachable_via_b[net_num_b]    — the bridge's port-B station
  reachable_via_b[255]             — broadcast slot
  reachable_via_a[255]             — broadcast slot

Called from the reset handler and also re-invoked at &E1D6 and
&E357 — probably after network topology changes or administrative
re-init. The &FF-marked slots prevent the bridge from being
confused by traffic to/from its own station IDs or broadcasts
during routing decisions.""")

comment(0xE424, "Y = 0, A = 0: set up to clear both tables")
comment(0xE428, "Zero reachable_via_b[Y]")
comment(0xE42B, "Zero reachable_via_a[Y]")
comment(0xE42F, "Loop over all 256 slots (Y wraps back to 0)")
comment(0xE431, "Marker value &FF for the special slots below")
comment(0xE433, "Port A bridge-station slot -> mark in reachable_via_a")
comment(0xE439, "Port B bridge-station slot -> mark in reachable_via_b")
comment(0xE43F, "Broadcast slot (255) in both maps")


# =====================================================================
# RAM test
# =====================================================================
# Reached by fall-through from the reset handler after the two ADLCs
# have been initialised. Scans pages from &1800 upward, writing &AA
# and &55 patterns through an indirect pointer and reading them
# back. The highest page that verifies is stored in top_ram_page
# (&82) as the top-of-RAM marker used later by workspace init.
#
# The INC on zero-page &00 between each write and read disturbs zero
# page — a non-existent or aliased target page then cannot pass the
# test on data-bus residue from the last write. This is a deliberate
# anti-aliasing defence rather than a counter.

label(0xE00B, "ram_test")
subroutine(0xE00B, "ram_test", hook=None, is_entry_point=False,
    title="Scan pages from &1800 upward; record top of RAM",
    description="""\
Probes pages upward from &1800 by writing &AA and &55 patterns
through mem_ptr_lo/mem_ptr_hi (&80/&81) and verifying each. The
highest page that verifies is stored in top_ram_page (&82), used
downstream by workspace initialisation. The Bridge can be built
with either one 8 KiB 6264 chip or four 2 KiB 6116 chips (chosen
by soldered links), so RAM size must be discovered at power-on.

The routine looks like a textbook two-pattern memory test but is
considerably more robust than a naive STA/LDA/CMP would be. Three
independent mechanisms have to fail simultaneously for it to
report RAM where none exists:

  1. The INC on zero-page &00 between each write and its matching
     read is an anti-bus-residue defence. When the 6502 writes to
     an unmapped address, no chip latches the value, but the data
     bus capacitance can hold the written byte long enough for
     the subsequent LDA to sample its own ghost. INC $00 is a
     read-modify-write that drives the data bus three times with
     values unrelated to the test pattern (the cycle-4 dummy
     write is a classic NMOS 6502 quirk that is exploited here),
     clobbering any residue of &AA or &55.

  2. The choice of &00 specifically is an alias tripwire. If the
     address decoder is miswired and the target address aliases
     into zero page, the obvious alias landing point is &00 — so
     disturbing &00 between write and read forces any alias-based
     false-positive to fail the CMP.

  3. The two patterns &AA and &55 are bitwise complements: a
     stuck bit is detected on whichever pattern it contradicts,
     and a single-value bus residue cannot spoof both checks
     simultaneously.

See docs/analysis/ram-test-anti-aliasing.md for the full
cycle-level analysis.""")

comment(0xE00B, "Y = 0 (indirect offset, used throughout)")
comment(0xE00D, "mem_ptr_lo = 0 (pages tested are page-aligned)")
comment(0xE00F, "mem_ptr_hi starts at &17; INC makes first test &18")

label(0xE013, "ram_test_loop")
comment(0xE013, "Advance to next page")
comment(0xE015, "Pattern 1: &AA (1010_1010)")
comment(0xE019, "Disturb ZP &00 -- defeat data-bus residue aliasing")
comment(0xE01B, "Read back pattern 1")
comment(0xE01F, "Pattern 1 mismatch -- end of RAM")
comment(0xE021, "Pattern 2: &55 (0101_0101)")
comment(0xE025, "Disturb ZP &00 again")
comment(0xE027, "Read back pattern 2")
comment(0xE02B, "Both patterns verified -- try next page")

label(0xE02D, "ram_test_done")
comment(0xE02D, "Back off: last-probed page did not verify")
comment(0xE02F, "Save top-of-RAM page to &82 for later use")
comment(0xE033, "Clear &0229 (flag, purpose TBD)")


# =====================================================================
# Build bridge-announcement frame for Econet side B
# =====================================================================

label(0xE458, "build_announce_b")
subroutine(0xE458, "build_announce_b", hook=None,
    title="Populate outbound frame with a side-B bridge announcement",
    description="""\
Populates the outbound frame control block at &045A-&0460 with
an all-broadcast bridge announcement carrying the B-side network
number as its payload. At reset time this is transmitted via
ADLC A first (announcing "network N is reachable through me" to
side A's stations), then tx_data0 is patched to net_num_a and it
is re-transmitted via ADLC B.

  tx_dst_stn = &FF                    broadcast station
  tx_dst_net = &FF                    broadcast network
  tx_src_stn = &18                    firmware marker (see below)
  tx_src_net = &18                    firmware marker (see below)
  tx_ctrl    = &80                    initial-announcement ctrl
  tx_port    = &9C                    bridge-protocol port
  tx_data0   = net_num_b              network number on side B

The src_stn/src_net fields are both set to the constant &18. The
Bridge has no station number of its own (only network numbers,
per the Installation Guide) so these fields are not real addresses.
Receivers do not use them for routing -- rx_a_handle_81 reads the
payload starting at offset 6 and ignores bytes 2-3 entirely. The
most plausible role for &18 is defensive redundancy: together with
dst=(&FF,&FF), ctrl=&80/&81 and port=&9C it gives a receiver
multiple ways to confirm that a received frame is a well-formed
bridge announcement.

Also writes &06 to tx_end_lo and &04 to tx_end_hi (so the transmit
routine sends bytes &045A..&0460 inclusive = 7 bytes when X=1),
loads X=1 (trailing-byte flag for transmit_frame_a), and points
mem_ptr at the frame block (&045A).

Called from the reset handler at &E038 and again from &E098 (the
main-loop periodic re-announce path). A structurally identical
cousin builder lives at sub_ce48d (&E48D) and is called from four
sites; it populates the same fields with values drawn from RAM
variables at rx_src_stn and rx_query_net rather than baked-in
constants.""")

comment(0xE458, "dst = &FFFF: broadcast station + network")
comment(0xE460, "src = &1818: firmware marker (Bridge has no station)")
comment(0xE468, "port = &9C (bridge-protocol port)")
comment(0xE46D, "ctrl = &80 (scout)")
comment(0xE472, "Payload byte 0: bridge's network number on side B")
comment(0xE478, "X = 1: probable side selector (B)")
comment(0xE47A, "tx command block: len=&06, ?=&04 (provisional)")
comment(0xE484, "mem_ptr = &045A (start of frame block)")


# =====================================================================
# Main Bridge loop (post-reset dispatcher)
# =====================================================================

label(0xE051, "main_loop")
subroutine(0xE051, "main_loop", hook=None, is_entry_point=False,
    title="Main Bridge loop: re-arm ADLCs, poll for frames, re-announce",
    description="""\
The Bridge's continuous-operation entry point. Reached by fall-
through from the reset handler once startup completes, and by JMP
from fourteen other sites — every routine that takes an "escape to
main" path (wait_adlc_a_idle, transmit_frame_a/b, etc.) lands
here, so main_loop is the anchor of every packet-processing cycle.

The header (&E051-&E078) forces each ADLC into a known RX-listening
state: if SR2 bit 0 or 7 (AP or RDA) is already set from a partial
or aborted previous operation, CR1 is cycled through &C2 (reset TX,
leave RX running) before setting it to &82 (TX in reset, RX IRQs
enabled). CR2 is set to &67 — the standard listen-mode value used
throughout the firmware.

The inner poll loop at main_loop_poll (&E079) tests SR1 bit 7 (IRQ
summary) on each ADLC in turn, with side B checked first. If either
chip has a pending IRQ, control jumps straight to the corresponding
frame handler; otherwise the idle path at main_loop_idle (&E089)
runs the periodic re-announcement.

The re-announce scheme uses three bytes of workspace:

  announce_flag   enables re-announce (bit 7 additionally selects
                  which side the re-announce goes out on)
  announce_tmr_   16-bit countdown, decremented every idle-path
    lo/hi         iteration; zero triggers the re-announce
  announce_count  remaining re-announce cycles; when this hits
                  zero, announce_flag is cleared and re-announce
                  stops until something else re-enables it

The re-announce path (&E098) rebuilds the announcement frame, sets
tx_ctrl to &81 (distinguishing it from the reset-time &80 first
announcement), then dispatches to side A or side B based on
announce_flag bit 7. The timer is re-armed to &8000 (32768 idle
iterations) after each announce, giving a roughly constant cadence
regardless of how busy the ADLCs are with other traffic.""")

comment(0xE051, "Check ADLC A for stale AP/RDA from previous activity")
comment(0xE058, "Reset A's TX path but leave RX running")
comment(0xE05D, "Arm CR1 A = &82: TX reset, RX IRQ enabled")
comment(0xE062, "Arm CR2 A = &67: standard listen-mode config")
comment(0xE067, "Same stale-state check for ADLC B")
comment(0xE073, "Arm CR1 B = &82 and CR2 B = &67")


label(0xE0E2, "rx_frame_a")
subroutine(0xE0E2, "rx_frame_a", hook=None, is_entry_point=False,
    title="Drain and dispatch an inbound frame on ADLC A",
    description="""\
Reached from main_loop_poll when ADLC A raises SR1 bit 7. Drains
the incoming scout frame from the RX FIFO into the rx_* buffer at
&023C-&024F, runs two levels of filtering, and then dispatches on
the control byte to per-message handlers.

Filtering stage 1 — addressing:

  Expect SR2 bit 0 (AP: Address Present) -- if missing, bail to
  main_loop (spurious IRQ).

  Read byte 0 (rx_dst_stn) and byte 1 (rx_dst_net). If rx_dst_net
  is zero (local net) or reachable_via_b[rx_dst_net] is zero (unknown
  network), jump to rx_a_not_for_us (&E13F): ignore the frame,
  re-listen, drop back to main_loop_poll without a full main_loop
  re-init.

Draining:

  Read the rest of the frame in byte-pairs into &023C+Y up to Y=20
  (the Bridge only keeps the first 20 bytes). After the drain,
  force CR1=0 and CR2=&84 to halt the chip and test SR2 bit 1
  (FV, Frame Valid). If FV is clear, the frame was corrupt or
  short -- bail to main_loop. If SR2 bit 7 (RDA) is also set,
  read one trailing byte.

Filtering stage 2 — broadcast check:

  Only frames with dst_stn == dst_net == &FF (full broadcast)
  proceed to the bridge-protocol dispatcher. Everything else
  falls to rx_a_forward (&E208), the cross-network forwarding
  path (not yet analysed).

Dispatch on rx_ctrl (after verifying rx_port == &9C = bridge
protocol):

  &80  ->  rx_a_handle_80  (&E1D6) - initial bridge announcement
  &81  ->  rx_a_handle_81  (&E1EE) - re-announcement
  &82  ->  rx_a_handle_82  (&E19D) - bridge query (tentative)
  &83  ->  rx_a_handle_83  (&E195) - bridge query, known-station
  other ->  rx_a_forward   (&E208) - forward or discard

The side-B handler at &E263 is the mirror of this routine.""")

comment(0xE0E2, "A = &01: mask SR2 bit 0 (AP: Address Present)")
comment(0xE0E7, "AP missing -> spurious IRQ, bail")
comment(0xE0E9, "Read byte 0: destination station")
comment(0xE0EF, "Wait for second IRQ: next byte ready")
comment(0xE0F5, "No second IRQ -> frame is truncated, bail")
comment(0xE0F7, "Read byte 1: destination network")
comment(0xE0FA, "dst_net == 0 (local net) -> not for us")
comment(0xE0FC, "dst_net not known in reachable_via_b -> not for us")
comment(0xE104, "Y = 2: start of pair-drain loop")

label(0xE106, "rx_frame_a_drain")
comment(0xE106, "Wait for next FIFO IRQ")
comment(0xE10C, "IRQ cleared -> end of frame body")
comment(0xE10E, "Read byte Y")
comment(0xE115, "Read byte Y+1 (pair for throughput)")
comment(0xE11C, "Stop at 20 bytes (header + 14 payload)")

label(0xE120, "rx_frame_a_end")
comment(0xE120, "Halt the ADLC: CR1=0, CR2=&84")
comment(0xE12A, "A = &02: mask SR2 bit 1 (FV: Frame Valid)")
comment(0xE12F, "No FV -> frame corrupt/short, bail")
comment(0xE131, "FV set but no RDA -> frame done, process it")
comment(0xE133, "FV + RDA: one trailing byte to drain")

label(0xE13C, "rx_frame_a_bail")
comment(0xE13C, "Bail: return to main_loop")

label(0xE13F, "rx_a_not_for_us")
comment(0xE13F, "Re-listen with CR1=&A2 (RX on, IRQ enabled)")
comment(0xE144, "Back to poll (skip main_loop re-arm)")

label(0xE147, "rx_a_to_forward")
comment(0xE147, "Dispatched to rx_a_forward at &E208")

label(0xE14A, "rx_frame_a_dispatch")
comment(0xE14A, "Save final byte count as rx_len")
comment(0xE14D, "Need >= 6 bytes for a valid scout header")
comment(0xE151, "Lazy-init rx_src_net if zero")
comment(0xE156, "Default src_net to net_num_a")
comment(0xE15C, "Is rx_dst_net addressing side B (= our B station)?")
comment(0xE164, "Yes: normalise rx_dst_net to 0 (local on B)")
comment(0xE169, "Broadcast test: both dst bytes == &FF?")
comment(0xE171, "Not broadcast -> forward path")
comment(0xE173, "Broadcast: re-arm A's listen mode")
comment(0xE17E, "Bridge-protocol port (&9C)?")
comment(0xE180, "Not bridge protocol -> forward")
comment(0xE182, "Dispatch on rx_ctrl")
comment(0xE185, "&81 -> re-announcement handler")
comment(0xE189, "&80 -> initial announcement handler")
comment(0xE18D, "&82 -> bridge query (shares &83 path)")
comment(0xE191, "&83 -> bridge query, known-station path")
comment(0xE195, "Station Y known in reachable_via_b?")
comment(0xE19B, "Unknown -> skip, back to main loop")


label(0xE316, "rx_b_handle_83")
subroutine(0xE316, "rx_b_handle_83", hook=None, is_entry_point=False,
    title="Side-B bridge query for a specific network (ctrl=&83)",
    description="""\
Mirror of rx_a_handle_83 (&E195) with A/B swapped: consults
reachable_via_a (not _b) because the frame arrived on side B.
Falls through to rx_b_handle_82 when the queried network is
known.""")

label(0xE31E, "rx_b_handle_82")
subroutine(0xE31E, "rx_b_handle_82", hook=None, is_entry_point=False,
    title="Side-B bridge general query (ctrl=&82)",
    description="""\
Mirror of rx_a_handle_82 (&E19D) with A/B swapped throughout:
delay-stagger seeded from net_num_a, transmit via ADLC B,
tx_src_net patched to net_num_a, response-data's ctrl encodes
net_num_b (the Bridge's B-side network). See rx_a_handle_82
for the full protocol description.""")

label(0xE357, "rx_b_handle_80")
subroutine(0xE357, "rx_b_handle_80", hook=None, is_entry_point=False,
    title="Side-B initial bridge announcement (ctrl=&80)",
    description="""\
Mirror of rx_a_handle_80 (&E1D6): wipe reachable_via_* via
init_reachable_nets, seed the re-announce timer's high byte
from net_num_a (mirror of A-side seeding from net_num_b), set
announce_count = 10 and announce_flag = &80 (bit 7 set = side B
selected). Falls through to rx_b_handle_81.""")

label(0xE36F, "rx_b_handle_81")
subroutine(0xE36F, "rx_b_handle_81", hook=None, is_entry_point=False,
    title="Side-B re-announcement (ctrl=&81); learn + re-forward",
    description="""\
Mirror of rx_a_handle_81 (&E1EE): reads each payload byte from
offset 6 onward as a network number reachable via side B, marks
reachable_via_b[x] = &FF for each (mirror of the A-side writing
reachable_via_a). Appends net_num_b to the payload and falls
through to rx_b_forward for re-broadcast onto side A.""")

label(0xE371, "rx_b_learn_loop")


label(0xE263, "rx_frame_b")
subroutine(0xE263, "rx_frame_b", hook=None, is_entry_point=False,
    title="Drain and dispatch an inbound frame on ADLC B",
    description="""\
Byte-for-byte mirror of rx_frame_a (&E0E2): same three-stage
structure (addressing filter, drain, broadcast + bridge-protocol
check), same control-byte dispatch, with `adlc_a_*` replaced by
`adlc_b_*`, `reachable_via_b` by `reachable_via_a`, and the side-selector
value swaps (`net_num_a` ↔ `net_num_b`) where appropriate.

Bridge-protocol dispatch for this side:

  &80  ->  rx_b_handle_80  (&E357) - initial bridge announcement
  &81  ->  rx_b_handle_81  (&E36F) - re-announcement
  &82  ->  rx_b_handle_82  (&E31E) - bridge query (shared &83 path)
  &83  ->  rx_b_handle_83  (&E316) - bridge query, known-station
  other ->  rx_b_forward   (&E389) - forward or discard

See rx_frame_a for the full per-instruction explanation.""")

label(0xE287, "rx_frame_b_drain")
label(0xE2A1, "rx_frame_b_end")
label(0xE2BD, "rx_frame_b_bail")
label(0xE2C0, "rx_b_not_for_us")
label(0xE2C8, "rx_b_to_forward")
label(0xE2CB, "rx_frame_b_dispatch")


label(0xE56E, "handshake_rx_a")
subroutine(0xE56E, "handshake_rx_a", hook=None,
    title="Receive a handshake frame on ADLC A and stage it for forward",
    description="""\
The receive half of four-way-handshake bridging for the A side.
Enables RX on ADLC A, drains an inbound frame byte-by-byte into
the outbound buffer starting at tx_dst_stn (&045A), then sets up
tx_end_lo/hi so the next call to transmit_frame_b transmits the
just-received frame out of the other port verbatim.

The drain is capped at `top_ram_page` (set by the boot RAM test)
so very long frames fill available RAM and no further.

After the drain, does three pieces of address fix-up on the
now-staged frame:

  * If tx_src_net (byte 3 of the frame) is zero, fill it with
    net_num_a. Many Econet senders leave src_net as zero to mean
    "my local network"; the Bridge makes that explicit before
    forwarding.

  * Reject the frame if tx_dst_net is zero (no destination
    network declared) or if reachable_via_b has no entry for
    that network (we don't know a route).

  * If tx_dst_net equals net_num_b (our own B-side network),
    normalise it to zero -- from side B's perspective the frame
    is now "local".

On any of the "reject" paths above, and on any sub-step that
fails (no AP/RDA, no Frame Valid, no response at all), takes
the standard escape-to-main-loop exit: PLA/PLA/JMP main_loop.

On success, return to the caller with mem_ptr / tx_end_lo / tx_end_hi
ready for transmit_frame_b (or transmit_frame_a in the reverse
direction for queries). Mirror of handshake_rx_b (&E5FF).

Called from five sites: &E1B5 and &E1D0 (rx_a_handle_82/83 query
paths), &E254 and &E3DB (forward tails), and &E3CF (also a forward
tail).""")

comment(0xE56E, "CR1 = &82: TX in reset, RX IRQs enabled")
comment(0xE573, "A = &01: mask SR2 bit 0 (AP)")
comment(0xE575, "Wait for the first RX event")
comment(0xE57B, "No AP: nothing arrived, escape to main")
comment(0xE57D, "Read byte 0: destination station")
comment(0xE589, "Second IRQ gone -> frame truncated, escape")
comment(0xE58B, "Read byte 1: destination network")
comment(0xE591, "Y = 2: continue draining pairs into (&045A)+Y")
comment(0xE599, "End-of-frame detected mid-pair")
comment(0xE5A9, "Advance to next page of the staging buffer")
comment(0xE5AD, "Stop if we would overrun available RAM")

comment(0xE5B1, "Escape to main (PLA/PLA/JMP pattern)")

comment(0xE5B6, "CR1=0, CR2=&84: halt chip post-drain")
comment(0xE5C5, "No Frame Valid -> corrupt/short, escape")
comment(0xE5C7, "FV set but no RDA -> drained, proceed")
comment(0xE5C9, "One trailing byte remained")
comment(0xE5CF, "Finalise tx_end_lo = byte count (rounded even)")
comment(0xE5D6, "If src_net was zero, normalise to net_num_a")
comment(0xE5E1, "Forwardability check on tx_dst_net")
comment(0xE5E4, "dst_net = 0 -> reject")
comment(0xE5E6, "Not reachable via side B -> reject")
comment(0xE5EB, "dst_net = net_num_b -> frame is local on B")
comment(0xE5F0, "...normalise to 0 for the outbound frame")
comment(0xE5F5, "tx_end_hi = final mem_ptr_hi (multi-page)")
comment(0xE5FA, "Reset mem_ptr_hi so transmit reads from &045A")


label(0xE5FF, "handshake_rx_b")
subroutine(0xE5FF, "handshake_rx_b", hook=None,
    title="Receive a handshake frame on ADLC B and stage it for forward",
    description="""\
Byte-for-byte mirror of handshake_rx_a (&E56E) with adlc_a_*
replaced by adlc_b_* and the A/B network-number swaps in the
address normalisation: src_net defaults to net_num_b, and the
forwardability check is against reachable_via_a.

Called from five sites: &E24E, &E25A, &E336, &E351, &E3D5.
See handshake_rx_a for the per-instruction explanation.""")


label(0xE48D, "build_query_response")
subroutine(0xE48D, "build_query_response", hook=None,
    title="Build a reply-scout frame addressed back to the querier",
    description="""\
A second frame-builder (sibling of build_announce_b) used by the
bridge-query response path. Where build_announce_b writes a
broadcast-addressed template, this one builds a unicast reply:

  tx_dst_stn = rx_src_stn          station that sent the query
  tx_dst_net = 0                   local network
  tx_src_stn = 0                   Bridge has no station
  tx_src_net = 0                   (caller patches to net_num_?)
  tx_ctrl    = &80                 scout control byte
  tx_port    = rx_query_port       response port from byte 12 of query
  X          = 0                   no trailing payload

Also writes tx_end_lo=&06 / tx_end_hi=&04 and points mem_ptr at
&045A so a subsequent transmit_frame_? sends the 6-byte scout.

Called from the two query-response paths (&E1A0 and &E1B8 on
side A; &E321 and &E339 on side B). Each caller then patches a
subset of the fields before calling transmit_frame_? -- the
idiomatic second call in particular overwrites tx_ctrl and
tx_port to carry the bridge's routing answer.""")

comment(0xE48D, "dst_stn = rx_src_stn: reply to the querier")
comment(0xE493, "dst_net = 0: reply on local network")
comment(0xE498, "src = (0, 0): Bridge has no station")
comment(0xE4A0, "ctrl = &80: scout")
comment(0xE4A5, "port = rx_query_port: from byte 12 of query")
comment(0xE4AB, "X = 0: no trailing payload byte")
comment(0xE4AD, "tx_end = &0406: 6-byte scout")
comment(0xE4B7, "mem_ptr = &045A: frame-block base")


label(0xE195, "rx_a_handle_83")
subroutine(0xE195, "rx_a_handle_83", hook=None, is_entry_point=False,
    title="Side-A bridge query for a specific network (ctrl=&83)",
    description="""\
Called when a received frame on side A is broadcast + port=&9C +
ctrl=&83. The frame is a bridge query asking 'can you reach
network X?', where X is carried in rx_query_net (byte 13 of the
payload).

Consults reachable_via_b[rx_query_net]. If the entry is zero, we
don't know how to reach that network and the query is dropped
(JMP main_loop via &E1D3). If non-zero, falls through to
rx_a_handle_82 to compose and send the reply.""")

comment(0xE195, "Y = rx_query_net: network being queried")
comment(0xE198, "Look up in reachable_via_b")
comment(0xE19B, "Unknown network -> silently drop the query")


label(0xE19D, "rx_a_handle_82")
subroutine(0xE19D, "rx_a_handle_82", hook=None, is_entry_point=False,
    title="Side-A bridge general query (ctrl=&82); also &83 target path",
    description="""\
Called when a received frame on side A is broadcast + port=&9C +
ctrl=&82 (a general bridge query), or when rx_a_handle_83 has
verified that the queried network is known to this Bridge. The
handler generates a two-frame bridge-query response, following
the standard Econet four-way handshake from the responder side:

  1. Build a reply scout via build_query_response -- addressed
     back to the querier on its local network, with tx_src_net
     patched to our net_num_b.

  2. Stagger the transmission using sub_ce448 with the delay
     counter seeded from net_num_b (so multiple bridges on the
     same segment don't collide responding to a broadcast query).

  3. CSMA, transmit the reply scout, then handshake_rx_a to
     receive the querier's scout-ACK.

  4. Rebuild the frame via build_query_response again and patch
     it into the response-data shape:
        tx_ctrl = net_num_a        "this Bridge serves side-A network"
        tx_port = rx_query_net     echoes the queried network
     The ctrl and port fields are being repurposed to carry the
     routing answer as two bytes of payload -- unusual but
     compact for a 6-byte scout-shaped frame.

  5. Transmit the response data frame, then handshake_rx_a for
     the final ACK. JMP main_loop on completion.

Either handshake_rx_a call can escape to main_loop if the
querier doesn't complete the handshake, aborting cleanly.""")

comment(0xE19D, "Re-arm A for listen after the received query")
comment(0xE1A0, "Build reply-scout template (unicast to querier)")
comment(0xE1A3, "Patch src_net with our B-side network number")
comment(0xE1A9, "Seed delay counter from net_num_b (stagger)")
comment(0xE1AC, "Delay before transmit -- collision avoidance")
comment(0xE1AF, "CSMA on A")
comment(0xE1B2, "Transmit reply scout (dst = querier)")
comment(0xE1B5, "Receive scout-ACK from querier")
comment(0xE1B8, "Rebuild frame for the data phase")
comment(0xE1C1, "Encode A-side network number into ctrl field")
comment(0xE1C7, "Echo queried network in port field")
comment(0xE1CD, "Transmit response data frame")
comment(0xE1D0, "Receive final handshake ACK")


label(0xE208, "rx_a_forward")
subroutine(0xE208, "rx_a_forward", hook=None, is_entry_point=False,
    title="Forward an A-side frame to B, completing the 4-way handshake",
    description="""\
Entry point for cross-network forwarding of frames received on
side A. Reached from three places:

  * rx_a_to_forward (&E147): the A-side frame is addressed to a
    remote station (not a full broadcast), and we have accepted
    it via the routing filter.
  * rx_frame_a ctrl dispatch fall-through (&E193): the frame is
    broadcast + port &9C but has a control byte outside the
    recognised bridge-protocol set (&80-&83).
  * Fall-through from rx_a_handle_81 (&E207): we've learned from
    the announcement and appended net_num_a to the payload; now
    propagate it onward.

The routine bridges the complete Econet four-way handshake by
alternating direct-forward, receive-on-one-side, and re-transmit:

  Stage 1 (SCOUT, A -> B): the inbound scout already sits in the
  rx_* buffer (&023C..). Round rx_len down to even, wait for B
  to be idle, then push the bytes directly into adlc_b_tx in
  pairs (odd-length frames send the trailing byte as a single
  write). Terminate by writing CR2=&3F (end-of-burst).

  Stage 2 (ACK1, B -> A): handshake_rx_b drains the receiver's
  ACK from ADLC B into the &045A staging buffer. transmit_frame_a
  forwards it to the originator.

  Stage 3 (DATA, A -> B): handshake_rx_a drains the sender's
  data frame from ADLC A into &045A. transmit_frame_b forwards
  it to the destination.

  Stage 4 (ACK2, B -> A): handshake_rx_b drains the receiver's
  final ACK. transmit_frame_a forwards it to the originator.

Each handshake_rx_? call can escape to main_loop (PLA/PLA/JMP) if
the expected frame doesn't arrive, cleanly aborting the bridged
conversation without further work on either side.

The A-B-A transmit pattern that appears at the routine's tail is
therefore the natural shape of a bridged four-way handshake when
the initial scout came from side A: two frames travel A -> B
(scout and data) and two travel B -> A (two ACKs).""")

comment(0xE208, "rx_len -> even-rounded byte count for pair loop")
comment(0xE20B, "X = original rx_len (preserved for odd-fix at end)")
comment(0xE211, "CSMA on side B before transmitting")
comment(0xE214, "Y = 0: rx buffer offset")
label(0xE216, "rx_a_forward_pair_loop")
comment(0xE216, "Wait for TDRA on B")
comment(0xE21C, "TDRA clear -> ADLC lost sync, escape to main")
comment(0xE21E, "Send byte Y (from rx buffer) as continuation")
comment(0xE225, "Send byte Y+1 (pair for throughput)")
comment(0xE22C, "Done at even length?")
comment(0xE231, "Recover original length to check parity")
comment(0xE232, "ROR: carry <- bit 0 (= original length was odd?)")
comment(0xE233, "Even -> skip trailing-byte path")
comment(0xE235, "Odd-length tail: wait for TDRA")
comment(0xE238, "...send the final byte")
label(0xE23E, "rx_a_forward_ack_round")
comment(0xE23E, "CR2 = &3F: end-of-burst (scout delivered)")
comment(0xE246, "Reset mem_ptr to &045A for the handshake staging")
comment(0xE24E, "Stage 2: receive ACK1 on B into &045A")
comment(0xE251, "...forward ACK1 to A")
comment(0xE254, "Stage 3: receive DATA on A into &045A")
comment(0xE257, "...forward DATA to B")
comment(0xE25A, "Stage 4: receive ACK2 on B into &045A")
comment(0xE25D, "...forward ACK2 to A")
label(0xE260, "rx_a_forward_done")
comment(0xE260, "Handshake complete -> back to main_loop")


label(0xE389, "rx_b_forward")
subroutine(0xE389, "rx_b_forward", hook=None, is_entry_point=False,
    title="Forward a B-side frame to A, completing the 4-way handshake",
    description="""\
Byte-for-byte mirror of rx_a_forward (&E208) with A and B swapped
throughout: the inbound scout is pushed via adlc_a_tx, and the
B-A-B tail bridges the four-way handshake the other direction.

Reached from rx_b_to_forward (&E2C8), from rx_frame_b's ctrl
dispatch fall-through (&E314), and from rx_b_handle_81's
fall-through at &E387.

See rx_a_forward for the full per-stage explanation.""")

label(0xE397, "rx_b_forward_pair_loop")
label(0xE3BF, "rx_b_forward_ack_round")
label(0xE3E1, "rx_b_forward_done")


label(0xE1D6, "rx_a_handle_80")
subroutine(0xE1D6, "rx_a_handle_80", hook=None, is_entry_point=False,
    title="Side-A initial bridge announcement (ctrl=&80)",
    description="""\
Called when a received frame on side A is broadcast + port=&9C +
ctrl=&80. An initial announcement means another bridge has just
come up (or announced fresh topology), so:

  1. Wipe all learned routing state via init_reachable_nets -- the
     network topology may have changed, so accumulated knowledge
     is suspect.

  2. Schedule a burst of our own re-announcements: ten cycles with
     a staggered initial timer value seeded from net_num_b. Using
     the network number as part of the timer phase means bridges
     on different networks won't step on each other's announces.
     announce_flag is set to &40 (enable, bit 7 clear = side A).

  3. Fall through to rx_a_handle_81, which processes the incoming
     payload and learns the networks it lists.""")

comment(0xE1D6, "Forget learned routes (topology change)")
comment(0xE1D9, "Seed timer high byte from our B-side net number")
comment(0xE1DF, "Timer low byte = 0")
comment(0xE1E4, "Queue 10 re-announces")
comment(0xE1E9, "Flag = &40 (enable, side A)")

label(0xE1EE, "rx_a_handle_81")
subroutine(0xE1EE, "rx_a_handle_81", hook=None, is_entry_point=False,
    title="Side-A re-announcement (ctrl=&81); learn + re-forward",
    description="""\
Also reached via fall-through from rx_a_handle_80. Processes the
announcement payload: each byte from offset 6 to rx_len is a
network number reachable through the announcer (and therefore,
from us, reachable by forwarding to side A). Mark each such
network in reachable_via_a.

After learning, append our own net_num_a to the payload and bump
rx_len. Falling through to rx_a_forward then re-broadcasts the
augmented announcement out of ADLC B, so any bridges beyond us
on that side hear about these networks -- plus us, as one more
hop along the route. Classic distance-vector flooding.""")

comment(0xE1EE, "Y = 6: start of announcement payload")
label(0xE1F0, "rx_a_learn_loop")
comment(0xE1F0, "Read next network number from payload")
comment(0xE1F3, "X = network number")
comment(0xE1F6, "Mark network X as reachable via side A")
comment(0xE1FA, "End of payload?")
comment(0xE1FF, "Append our net_num_a to the payload")
comment(0xE205, "Bump the frame length by one byte")


label(0xE079, "main_loop_poll")
comment(0xE079, "Test SR1 bit 7 on B (IRQ summary)")
comment(0xE07C, "No IRQ on B, check A")
comment(0xE07E, "B IRQ: hand off to side-B frame handler")
comment(0xE081, "Test SR1 bit 7 on A (IRQ summary)")
comment(0xE084, "No IRQ on A, drop to idle path")
comment(0xE086, "A IRQ: hand off to side-A frame handler")

label(0xE089, "main_loop_idle")
comment(0xE089, "Re-announce enabled?")
comment(0xE08C, "No: go back to polling the ADLCs")
comment(0xE08E, "Yes: decrement 16-bit re-announce timer")
comment(0xE091, "Still ticking, back to poll")
comment(0xE093, "LSB wrapped, tick MSB too")
comment(0xE096, "Still ticking, back to poll")

label(0xE098, "re_announce")
subroutine(0xE098, "re_announce", hook=None, is_entry_point=False,
    title="Periodic re-announcement of the bridge on one side",
    description="""\
Reached from the idle path once the 16-bit announce_tmr has
ticked down to zero. Rebuilds the announcement frame via
build_announce_b (same template used at reset), then patches
tx_ctrl to &81 — the &80 value written by build_announce_b is
the initial/first-broadcast control byte, while &81 is the
re-announce variant. The receiving stations can presumably
distinguish first-seen-bridge from follow-up announcements by
this single bit.

Which side to transmit on is selected by announce_flag bit 7:

  bit 7 clear (flag = 1..&7F)  ->  transmit via ADLC A (side A)
  bit 7 set   (flag = &80..FF) ->  transmit via ADLC B (side B,
                                   after patching tx_data0 with
                                   net_num_a, mirroring the
                                   reset-time dual-broadcast)

Each visit decrements announce_count. If it hits zero, announce_
flag is cleared and periodic re-announce stops (re_announce_done).
Otherwise the timer is re-armed to &8000 and control returns to
main_loop (re_announce_rearm).

Before transmitting on one side, the routine resets the OTHER
ADLC's TX path (CR1 = &C2) — this prevents the opposite side from
accidentally transmitting a collision during our operation.""")

comment(0xE098, "Rebuild the frame template (dst=FF, ctrl=&80, ...)")
comment(0xE09B, "Patch ctrl = &81 (re-announce variant)")
comment(0xE0A0, "Test announce_flag bit 7: which side?")
comment(0xE0A3, "Bit 7 set -> transmit via side B")
comment(0xE0A5, "Side A path: reset B's TX first (no collision)")
comment(0xE0AA, "Wait for A's line to go idle then transmit")
comment(0xE0B0, "Count this announce; stop if exhausted")

label(0xE0B5, "re_announce_rearm")
comment(0xE0B5, "Re-arm timer to &8000 (32K idle iterations)")
comment(0xE0BF, "Back to main loop")

label(0xE0C2, "re_announce_done")
comment(0xE0C2, "announce_count exhausted: disable re-announce")
comment(0xE0C7, "Back to main loop")

label(0xE0CA, "re_announce_side_b")
comment(0xE0CA, "Side B path: patch tx_data0 for side-B broadcast")
comment(0xE0D0, "Reset A's TX first (mirror of side-A path)")
comment(0xE0D5, "Wait for B's line to go idle then transmit")
comment(0xE0DB, "Count this announce; stop if exhausted")
comment(0xE0E0, "Not exhausted -> re_announce_rearm (ALWAYS branch)")


# =====================================================================
# Transmit a frame via ADLC A
# =====================================================================

label(0xE517, "transmit_frame_a")
subroutine(0xE517, "transmit_frame_a", hook=None,
    title="Send the frame at mem_ptr out through ADLC A's TX FIFO",
    description="""\
Sends the frame starting at mem_ptr (&80/&81 — normally pointing at
the outbound control block &045A) through ADLC A's TX FIFO. Termi-
nation is controlled by the 16-bit pointer tx_end_lo/tx_end_hi
(&0200/&0201): the loop sends byte pairs until mem_ptr + Y reaches
or passes (tx_end_hi:tx_end_lo). X is a flag — non-zero means send
one extra trailing byte after the terminator (used by builders that
append a payload like build_announce_b's net_num_b at &0460).

On entry:
  mem_ptr_lo/hi                      start address of frame
  tx_end_lo/hi                       end address (exclusive pair)
  X                                  0 = no trailing byte,
                                     1 = send one trailing byte
  ADLC A must already be primed by a frame builder

On exit (normal RTS):
  mem_ptr_lo/hi reset to &045A       ready for next builder
  ADLC A's TX FIFO flushed, CR2 = &3F

Abnormal exit: if any of the three wait_adlc_a_irq polls returns
with SR1's V-bit clear instead of set (meaning the ADLC didn't reach
the expected TDRA state), the routine drops the caller's return
address from the stack and JMP's into the main loop at &E051 —
the same escape-to-main pattern used by wait_adlc_a_idle.

Called from seven sites: reset (&E03E), &E0AD, &E1B2, &E1CD, &E251,
&E25D, &E3D8.""")

comment(0xE517, "CR2 = &E7: prime for TX (FC_TDRA, 2-byte, PSE+extras)")
comment(0xE51C, "CR1 = &44: arm TX interrupts")
comment(0xE521, "Y = 0 (buffer offset into frame)")
comment(0xE523, "Wait for ADLC A to flag TDRA")
comment(0xE526, "Test SR1 V-flag (TDRA bit 6)")
comment(0xE529, "V set -> room in FIFO, send next pair")
comment(0xE52B, "V clear: abandon frame and escape to main loop")
comment(0xE530, "Load and send frame byte Y")
comment(0xE536, "Load and send frame byte Y+1")
comment(0xE53C, "Y wrapped: bump mem_ptr_hi")
comment(0xE540, "Terminate once Y == tx_end_lo and hi == tx_end_hi")
comment(0xE54C, "X!=0: send one more trailing byte (X bit 0 only)")
comment(0xE550, "Wait for TDRA before trailing byte")
comment(0xE556, "V clear -> escape (mirror of &E52B)")
comment(0xE558, "Send trailing byte (tx_data0 in announce frames)")
comment(0xE55D, "CR2 = &3F: signal end of burst, wait for completion")
comment(0xE565, "Reset mem_ptr to &045A for next builder")


# =====================================================================
# Transmit a frame via ADLC B (mirror of transmit_frame_a)
# =====================================================================

label(0xE4C0, "transmit_frame_b")
subroutine(0xE4C0, "transmit_frame_b", hook=None,
    title="Send the frame at mem_ptr out through ADLC B's TX FIFO",
    description="""\
Byte-for-byte mirror of transmit_frame_a (&E517) with adlc_a_*
replaced by adlc_b_*. Everything there applies here — same entry
conditions, same end-pointer semantics (tx_end_lo/hi), same X=0/1
trailing-byte flag, same escape-to-main-loop on unexpected SR1
state, same normal exit that resets mem_ptr to &045A.

Called from seven sites: reset (&E04E), &E0D8, &E257, &E333, &E34E,
&E3D2, &E3DE.""")


# =====================================================================
# Poll ADLC B for activity, or escape to the main loop
#  (mirror of wait_adlc_a_idle)
# =====================================================================

label(0xE690, "wait_adlc_b_idle")
subroutine(0xE690, "wait_adlc_b_idle", hook=None,
    title="Wait for ADLC B's line to go idle (CSMA) or escape",
    description="""\
Byte-for-byte mirror of wait_adlc_a_idle (&E6DC) with adlc_a_*
replaced by adlc_b_*. Same pre-transmit carrier-sense semantics:
wait for SR2 bit 2 (Rx Idle), back off on AP/RDA, escape to main
loop on ~131K-iteration timeout.

Called from four sites: reset (&E04B), &E0D5, &E211, &E330.""")


# =====================================================================
# Poll ADLC A for activity, or escape to the main loop
# =====================================================================

label(0xE6DC, "wait_adlc_a_idle")
subroutine(0xE6DC, "wait_adlc_a_idle", hook=None,
    title="Wait for ADLC A's line to go idle (CSMA) or escape",
    description="""\
Pre-transmit carrier-sense: polls ADLC A's SR2 until the Rx Idle
bit goes high (SR2 bit 2 = 15+ consecutive 1s received, i.e. the
line is quiet and it is safe to start a frame). A 24-bit timeout
counter at ctr24_lo/mid/hi (&0214-&0216) starts at &00_00_FE and
increments LSB-first; overflow takes ~131K iterations, a few
seconds at typical bus speeds.

Each iteration re-primes CR2 with &67 (clear TX/RX status,
FC_TDRA, 2/1-byte, PSE) then reads SR2. Three outcomes:

  * SR2 bit 2 set (Rx Idle): line is quiet. Arm CR2=&E7 and
    CR1=&44, RTS -- caller proceeds to transmit.

  * SR2 bit 0 or bit 7 set (AP or RDA): another station is
    sending into this ADLC. Back off by cycling CR1 through
    &C2 -> &82 (reset TX without touching RX) and keep polling.
    The Bridge is not the right place to assert on a busy line.

  * Timeout (counter overflows without ever seeing Rx Idle):
    PLA/PLA discards the caller's saved return address from the
    stack and JMP &E051 escapes into the main Bridge loop. The
    code between the caller's JSR and the main loop is skipped
    entirely. See docs/analysis/escape-to-main-control-flow.md.

Called from four sites, always immediately before a transmit:
reset (&E03B, before transmit_frame_a), &E0AA, &E1AF, &E392.""")

comment(0xE6DC, "Timeout counter = &00_00_FE (~131K iterations)")
comment(0xE6E9, "(spurious SR2 read; Z/N set but A overwritten below)")
comment(0xE6EC, "Y = &E7: CR2 value written on Rx-Idle exit")
comment(0xE6EE, "Re-prime CR2 = &67: clear status, FC_TDRA etc.")
comment(0xE6F3, "A = &04 for the BIT: test SR2 bit 2 (Rx Idle)")
comment(0xE6F8, "Rx Idle -> line quiet, exit to transmit via &E71F")
comment(0xE6FD, "Mask AP (bit 0) and RDA (bit 7) -- incoming data?")
comment(0xE6FF, "Neither -> line busy but nothing for us, keep polling")
comment(0xE701, "CR1 tickle: reset TX while another station sends")
comment(0xE70B, "Bump 24-bit timeout counter (LSB first)")
comment(0xE71A, "Timeout: drop caller's return address from stack...")
comment(0xE71C, "...and jump straight to the main Bridge loop")
comment(0xE71F, "Rx Idle seen: arm CR2 and CR1 ready for transmit")
comment(0xE727, "Normal return: caller may now transmit")


# =====================================================================
# Self-test (IRQ/BRK vector target)
# =====================================================================
# Entered when the push-button on the 6502 ~IRQ line is pressed. The
# operator's guide warns not to press this while connected to a live
# network — consistent with a routine that drives the ADLCs for
# diagnostic/loopback purposes (the typical use is with a cable
# looping the two Econet ports back to each other).
#
# Structure (first half annotated here; deeper tests to follow):
#   &F000  entry — disable interrupts, clear &03, fall into...
#   &F005  forcibly reset and re-init both ADLCs (differs subtly
#          from the normal adlc_*_full_reset path: CR2 is set to
#          &80 then reprogrammed, used when the previous state is
#          unknown)
#   &F02F  zero-page integrity test (&00, &01, &02 with &55/&AA)
#   &F04C  ROM checksum — sum all 8192 bytes mod 256; expected &55
#   &F070  deeper RAM test (TBD)
#   &F2C7  common failure handler — error code in A, signalled via
#          ADLC A (probable blink code)

subroutine(0xF000, "self_test", hook=None,
    title="Self-test entry (IRQ/BRK vector target)",
    description="""\
Invoked by pressing the self-test push-button on the 6502 ~IRQ
line (and, implicitly, by any BRK instruction in the ROM). Runs
through a sequence of hardware checks, signalling any failure
via self_test_fail at &F2C7 with an error code in A.

Not to be pressed while the Bridge is connected to a live
network: the self-test reconfigures the ADLCs and drives their
control registers in ways that will disturb any in-flight frames.
Typical usage is with a loopback cable between the two Econet
ports.""")

comment(0xF000, "Disable interrupts during self-test")
comment(0xF001, "Clear &03 (self-test scratch)")

label(0xF005, "self_test_reset_adlcs")
subroutine(0xF005, "self_test_reset_adlcs", hook=None,
    is_entry_point=False,
    title="Reset both ADLCs and light the status LED",
    description="""\
Byte-for-byte identical to the adlc_*_full_reset pair except for
one crucial detail: CR3 is programmed to &80 (bit 7 set) instead
of &00. CR3 bit 7 is the MC6854's LOC/DTR control bit — but the
pin it drives is inverted: when the control bit is HIGH, the pin
output goes LOW. On ADLC B (IC18) that pin sinks the low side of
the front-panel status LED (which has its high side tied through
a resistor to Vcc), so CR3 bit 7 = 1 pulls current through the
LED and lights it. ADLC A's LOC/DTR pin is not wired and gets the
same write for code symmetry only.

Re-entered at &F26C after certain test paths need to reset the
chips again; the LED stays lit until a normal reset runs
adlc_b_full_reset and clears CR3.""")

comment(0xF005, "CR1=&C1: reset TX+RX, AC=1 (both ADLCs)")
comment(0xF00D, "CR4=&1E (both): 8-bit RX, abort extend, NRZ")
comment(0xF015, "CR3=&80 (both): bit 7=1 -> LOC/DTR pin LOW (inverted)")
comment(0xF01A, "On ADLC B -> LED ON; on ADLC A pin NC, no effect")
comment(0xF01F, "CR1=&82 (both): TX in reset, AC=0; CR3 values persist")
comment(0xF027, "CR2=&67 (both): clear status, FC_TDRA, 2/1-byte, PSE")

label(0xF02F, "self_test_zp")
subroutine(0xF02F, "self_test_zp", hook=None, is_entry_point=False,
    title="Zero-page integrity test (&00-&02)",
    description="""\
Writes &55 to &00, &01, &02 and reads them back; then &AA and
reads back. Failure jumps to self_test_fail with A=1.

Tests only the three ZP bytes that are used as scratch by the
later self-test stages (ROM checksum, RAM scan). A full ZP test
isn't needed — the main reset handler has already exercised ZP
indirectly via the RAM test.""")

comment(0xF02F, "First pattern: &55")
comment(0xF043, "If pattern was &AA, ZP test done")
comment(0xF047, "Second pattern: &AA, loop back through the test")

label(0xF04C, "self_test_rom_checksum")
subroutine(0xF04C, "self_test_rom_checksum", hook=None,
    is_entry_point=False,
    title="ROM checksum",
    description="""\
Sums every byte of the 8 KiB ROM modulo 256 using a running A
accumulator. Expected total is &55; on mismatch, jumps to
self_test_fail with A=2.

Runtime pointer in &00/&01 starts at &E000; &02 holds the page
counter (32 pages = 8 KiB).""")

comment(0xF04C, "Pointer &00/&01 = &E000 (ROM base)")
comment(0xF050, "&02 = 32 (pages to sum)")
comment(0xF058, "Running total starts at A=Y=0")
comment(0xF05C, "Add next ROM byte to running sum")
comment(0xF061, "Advance to next page")
comment(0xF067, "Expected total: &55")
comment(0xF06B, "Fail code 2: ROM checksum")

label(0xF2C7, "self_test_fail")
subroutine(0xF2C7, "self_test_fail", hook=None,
    title="Self-test failure — signal error code via ADLC A",
    description="""\
Common failure exit from all self-test stages. Called with the
error code in A. Save two copies of the code in &00/&01 then
toggle adlc_a_cr2 in a timed pattern that probably drives a
visible indicator (status LED or loopback-cable signal) with a
blink count corresponding to the error code.

Reached from 7 sites: ROM checksum (&F06D, code 2), and six
other failure points at &F102, &F107, &F153, &F1F4, &F255,
&F261 (codes still to be identified).""")


# =====================================================================
# Generate output
# =====================================================================

output = go(print_output=False)

_output_dirpath.mkdir(parents=True, exist_ok=True)
output_filepath = _output_dirpath / "econet-bridge-1.asm"
output_filepath.write_text(output)
print(f"Wrote {output_filepath}", file=sys.stderr)

try:
    structured = get_structured()
    json_filepath = _output_dirpath / "econet-bridge-1.json"
    json_filepath.write_text(json.dumps(structured))
    print(f"Wrote {json_filepath}", file=sys.stderr)
except (AssertionError, Exception) as e:
    print(f"Warning: JSON output skipped: {e}", file=sys.stderr)
