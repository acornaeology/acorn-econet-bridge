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
#   74LS244 buffers that expose the station-number selection links
#   (one per Econet port).
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

label(0xC000, "station_id_a")   # Read: Econet port A station number
label(0xD000, "station_id_b")   # Read: Econet port B station number

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
comment(0xE414, "CR3=&00: normal; bit 7 = 0 -> LOC/DTR low -> status LED OFF")

label(0xE419, "adlc_b_listen")
subroutine(0xE419, "adlc_b_listen", hook=None,
    title="Enter ADLC B RX listen mode",
    description="""\
Mirror of adlc_a_listen for ADLC B.""")

comment(0xE419, "CR1=&82: TX in reset, RX interrupts enabled")
comment(0xE41E, "CR2=&67: clear status, FC_TDRA, 2/1-byte, PSE")


# =====================================================================
# Per-station tables for the two Econet ports
# =====================================================================
# Two 256-byte arrays indexed by station number (0-255). Their
# exact semantics (reachability / last-seen / TTL) will firm up as
# the code that reads them is analysed, but the init routine at
# &E424 shows the structure clearly: start cleared, then for each
# table mark the bridge's own station on the _other_ port plus the
# broadcast slot (&FF) with &FF. Named `_map` for now — refine as
# we learn more.

label(0x025A, "net_a_map")   # 256-entry table indexed by station id
label(0x035A, "net_b_map")

# Multi-byte counter reused for different purposes by several
# routines. adlc_a_poll_or_escape (&E6DC) uses all three bytes as a
# 24-bit timeout; sub_ce448 (&E448) uses only the low byte as an
# 8-bit delay counter. Byte-aligned rather than semantic names so the
# shared use is explicit.
label(0x0214, "ctr24_lo")
label(0x0215, "ctr24_mid")
label(0x0216, "ctr24_hi")

# Outbound-frame control block at &045A-&0460. Populated by various
# "frame builder" subroutines, then consumed by the transmit path
# (via mem_ptr at &80/&81 = &045A). Field names follow the Acorn
# Econet frame-header convention — provisional until the transmit
# routine is fully analysed.
label(0x045A, "tx_dst_stn")   # destination station (255 = broadcast)
label(0x045B, "tx_dst_net")   # destination network (255 = broadcast)
label(0x045C, "tx_src_stn")   # source station (provisional)
label(0x045D, "tx_src_net")   # source network (provisional)
label(0x045E, "tx_ctrl")      # control byte (scout flags)
label(0x045F, "tx_port")      # port number (protocol selector)
label(0x0460, "tx_data0")     # first payload byte


# =====================================================================
# Initialise per-station tables
# =====================================================================

label(0xE424, "init_station_maps")
subroutine(0xE424, "init_station_maps", hook=None,
    title="Clear the per-port station maps and mark bridge/broadcast",
    description="""\
Zeroes net_a_map and net_b_map (256 bytes each), then writes &FF
to three slots:

  net_b_map[station_id_a]    — the bridge's port-A station
  net_a_map[station_id_b]    — the bridge's port-B station
  net_a_map[255]             — broadcast slot
  net_b_map[255]             — broadcast slot

Called from the reset handler and also re-invoked at &E1D6 and
&E357 — probably after network topology changes or administrative
re-init. The &FF-marked slots prevent the bridge from being
confused by traffic to/from its own station IDs or broadcasts
during routing decisions.""")

comment(0xE424, "Y = 0, A = 0: set up to clear both tables")
comment(0xE428, "Zero net_a_map[Y]")
comment(0xE42B, "Zero net_b_map[Y]")
comment(0xE42F, "Loop over all 256 slots (Y wraps back to 0)")
comment(0xE431, "Marker value &FF for the special slots below")
comment(0xE433, "Port A bridge-station slot -> mark in net_b_map")
comment(0xE439, "Port B bridge-station slot -> mark in net_a_map")
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
an all-broadcast bridge announcement aimed at Econet side B:

  tx_dst_stn = &FF                    broadcast station
  tx_dst_net = &FF                    broadcast network
  tx_src_stn = &18                    provisional bridge id (TBD)
  tx_src_net = &18                    provisional bridge id (TBD)
  tx_ctrl    = &80                    scout control byte
  tx_port    = &9C                    bridge-protocol port
  tx_data0   = station_id_b           bridge's station on side B

Also writes &06 to &0200 and &04 to &0201 (purpose provisional:
probable length/selector fields in a separate transmit-command
block), loads X=1 (likely side selector: 0 = side A, 1 = side B),
and points mem_ptr at the frame block (&045A).

Called from the reset handler at &E038 and again from &E098. A
structurally identical cousin builder lives at sub_ce48d (&E48D)
and is called from four sites; it populates the same fields with
values drawn from RAM variables at &023E and &0248 rather than
baked-in constants.""")

comment(0xE458, "dst = &FFFF: broadcast station + network")
comment(0xE460, "src = &1818: provisional bridge self-id")
comment(0xE468, "port = &9C (bridge-protocol port)")
comment(0xE46D, "ctrl = &80 (scout)")
comment(0xE472, "Payload byte 0: bridge's station id on side B")
comment(0xE478, "X = 1: probable side selector (B)")
comment(0xE47A, "tx command block: len=&06, ?=&04 (provisional)")
comment(0xE484, "mem_ptr = &045A (start of frame block)")


# =====================================================================
# Poll ADLC A for activity, or escape to the main loop
# =====================================================================

label(0xE6DC, "adlc_a_poll_or_escape")
subroutine(0xE6DC, "adlc_a_poll_or_escape", hook=None,
    title="Poll ADLC A with ~2s timeout; on timeout bypass caller",
    description="""\
Polls ADLC A's SR2 with a 24-bit timeout counter at ctr24_lo/mid/hi
(&0214-&0216), initialised to &00_00_FE. The counter is incremented
LSB-first every iteration, giving roughly 131K iterations (a few
seconds at typical bus speeds) before overflow.

Each iteration re-primes CR2 with &67 (clear TX/RX status, FC_TDRA,
2/1-byte, PSE), then reads SR2. Three outcomes:

  * SR2 bit 2 set (mid-poll): activity detected. Configure the chip
    for the expected follow-up (CR2=&E7, CR1=&44) and RTS back to
    the caller -- the normal return path.

  * SR2 bit 0 or bit 7 set (AP or IRQ): tickle CR1 through
    &C2 -> &82 to reset TX without disturbing the RX state machine,
    then continue polling. This rides out incomplete frames or
    stale flags.

  * Timeout (counter overflows with none of the above): PLA/PLA
    discards the caller's saved return address from the stack and
    JMP &E051 bypasses into the main Bridge loop. The code between
    the caller's JSR and the main loop is therefore *skipped
    entirely* when the poll times out.

Called from four sites: reset (&E03B), &E0AA, &E1AF, &E392. Every
caller must accept that the routine may not return normally --
anything the caller intended to do after the JSR is abandoned on
timeout.""")

comment(0xE6DC, "Timeout counter = &00_00_FE (~131K iterations)")
comment(0xE6E9, "(spurious SR2 read; Z/N set but A overwritten below)")
comment(0xE6EC, "Y = &E7: CR2 value written on activity-detected exit")
comment(0xE6EE, "Re-prime CR2 = &67: clear status, FC_TDRA etc.")
comment(0xE6F3, "A = &04 for the next BIT: test SR2 bit 2")
comment(0xE6F8, "Bit 2 set -> activity detected, exit via &E71F")
comment(0xE6FD, "Mask AP (bit 0) and IRQ (bit 7)")
comment(0xE6FF, "Neither set -> no frame in progress, skip tickle")
comment(0xE701, "CR1 tickle: reset TX without touching RX")
comment(0xE70B, "Bump 24-bit timeout counter (LSB first)")
comment(0xE71A, "Timeout: drop caller's return address from stack...")
comment(0xE71C, "...and jump straight to the main Bridge loop")
comment(0xE71F, "Activity exit: arm CR2 and CR1 for what's next")
comment(0xE727, "Normal return to caller")


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
of &00. Bit 7 of CR3 drives the MC6854's LOC/DTR output pin; on
ADLC B (IC18) that pin drives the high side of the front-panel
status LED. Writing &80 here lights the LED, advertising that
self-test is in progress. ADLC A's LOC/DTR pin is not wired and
receives the same write for code symmetry only.

Re-entered at &F26C after certain test paths need to reset the
chips again; the LED stays lit until a normal reset runs
adlc_b_full_reset and clears CR3.""")

comment(0xF005, "CR1=&C1: reset TX+RX, AC=1 (both ADLCs)")
comment(0xF00D, "CR4=&1E (both): 8-bit RX, abort extend, NRZ")
comment(0xF015, "CR3=&80 (both): bit 7 = 1 -> ADLC B LOC/DTR high")
comment(0xF01A, "Same write to ADLC A: no visible effect (pin NC)")
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
