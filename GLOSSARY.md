# Glossary

Acorn Econet Bridge and Econet-related terminology.


**Econet**
: Acorn's low-cost local area network for the BBC Micro and other Acorn machines. Uses a two-wire twisted-pair bus with a single clock source and a collision-detection protocol, supporting up to 254 stations per segment.


**Bridge**
: A device that joins two Econet network segments, forwarding frames addressed to stations on the far side while isolating local traffic. Operates at the frame level and rewrites station/network numbers as frames cross between segments.


**Station**
: A node on an Econet network, identified by an 8-bit station number (1-254). Station 0 means "this station" (the local machine); station 255 is broadcast.


**Network number**
: An 8-bit identifier for an Econet segment. Frames crossing a bridge carry both the source and destination network numbers in addition to the station numbers.


**Frame**
: A single transmitted unit on Econet. Starts with a four-byte header (`dst_stn`, `dst_net`, `src_stn`, `src_net`), optionally continues with `ctrl` and `port` bytes in a scout, then payload, then the HDLC-appended CRC.

  HDLC flag bytes (`&7E`) delimit the frame on the wire and are never seen by software — the ADLC strips them on receive and inserts them on transmit.


**Scout**
: The first frame of a four-way handshake — a six-byte header (no payload) that tells the receiving station "I'm about to send you N bytes on port P". The receiver replies with a scout-ACK, then the sender transmits the data frame, and the receiver sends a final data-ACK.

  The Bridge's bridge-protocol frames (BridgeReset, BridgeReply, WhatNet, IsNet) are carried as scouts (or scout-then-data pairs) on port `&9C`.


**Four-way handshake**
: The standard Econet transaction: sender transmits a scout, receiver sends scout-ACK, sender transmits data, receiver sends data-ACK. All four frames are CRC-protected; any missing or corrupt frame aborts the transaction.

  The Bridge forwards complete four-way handshakes across its two segments by alternating receive-and-stage on one side with retransmit on the other — see `rx_a_forward` / `rx_b_forward` and the *Bridging the four-way handshake* writeup.


**Port**
: The 8-bit demux field in an Econet frame header that identifies which service the frame is addressed to — analogous to a TCP/UDP port number. `&9C` is the bridge-protocol port; other values are used by file servers, printer servers, and user-level applications.


**Broadcast**
: A frame addressed to `(dst_stn = 255, dst_net = 255)` — intended for every station on every segment. Stations filter incoming broadcasts by port and ctrl-byte; the Bridge relays them across segments only when they carry the bridge-protocol port (`&9C`).


**BridgeReset** (ctrl=&80 on port &9C)
: A broadcast scout a bridge emits when it first comes up, announcing "there is a new bridge here; forget what you thought you knew about routes". Receiving a BridgeReset wipes the recipient's routing tables and triggers a burst of re-announcements.


**BridgeReply** (ctrl=&81 on port &9C)
: A broadcast scout carrying a variable-length list of network numbers the sender can reach. Receivers record each network as reachable via the sender, append their own network number to the list, and re-broadcast the augmented frame onto the other side — distance-vector flooding.

  Unlike BridgeReset, receiving a BridgeReply does not itself schedule further re-announcements. If it did, two bridges would cascade forever.


**WhatNet** (ctrl=&82 on port &9C)
: A broadcast query asking "which networks do you reach?". Every bridge that hears the query responds with a two-frame exchange (scout + data) naming one of its own network numbers and one of the networks it can reach via the other side.


**IsNet** (ctrl=&83 on port &9C)
: A broadcast query asking "can you reach network X?", where X is the byte at offset 13 of the payload. Only bridges that have a route to X bother to respond; the response format is identical to a WhatNet reply.


**CSMA** (Carrier Sense Multiple Access)
: The access-control protocol for the shared Econet line: before transmitting, a station waits for the line to be idle (no other station is transmitting) to avoid collisions on the shared medium.

  The Bridge implements CSMA in `wait_adlc_a_idle` / `wait_adlc_b_idle`, which poll the ADLC's SR2 Rx-Idle bit before every outbound frame and escape to `main_loop` if the line never settles.


**NRZ** (Non-Return-to-Zero)
: The bit-encoding scheme the ADLC is configured for by `CR4 = &1E` during reset: each bit is transmitted as a steady high or low voltage for one bit time. Clock recovery at the receiver relies on transitions induced by HDLC's bit-stuffing rule rather than a separate clock wire.


**ADLC** (Advanced Data-Link Controller)
: The SY6854/MC6854 chip used by Acorn's Econet interface to perform the line-level HDLC framing, CRC generation, and collision detection. The Econet Bridge hardware has an ADLC for each of its two network ports.

  Each chip is accessed through four consecutive I/O addresses (ADLC A at `&C800-&C803`; ADLC B at `&D800-&D803`) that expose control registers CR1-CR4 on write and status registers SR1-SR2 on read, multiplexed by the Address Control (AC) bit in CR1: when AC is low, offsets 0-1 access CR1/CR2 and SR1/SR2; when AC is high, offsets 0-1 access CR3/CR4. Status bits consulted by the Bridge include AP, RDA, TDRA, and FV; less frequently OVRN (receiver overrun), CTS (Clear To Send), and DCD (Data Carrier Detect).


**HDLC** (High-level Data Link Control)
: ISO-standardised framing protocol for serial data links. Defines the flag bytes (`&7E`) that delimit frames, a 16-bit CRC field appended to each frame, and a "bit stuffing" rule that prevents flag bytes appearing inside payload data.

  The MC6854 ADLC implements HDLC in hardware, so the 6502 only sees decoded payload bytes from inside the flag-delimited frame. HDLC and ADCCP are essentially the same protocol under two different standards bodies' names.


**ADCCP** (Advanced Data Communications Control Procedures)
: ANSI's name for the same synchronous data-link protocol that ISO calls HDLC. The MC6854 ADLC datasheet uses both names interchangeably.


**CRC** (Cyclic Redundancy Check)
: A polynomial checksum the ADLC appends to every outbound frame and verifies on every inbound frame. Corrupt frames are flagged by clearing the Frame Valid (FV) bit in SR2; the CRC bytes themselves never reach the 6502.


**AP** (Address Present)
: An ADLC SR2 status bit (bit 0) that is set when the first byte of a received frame is in the RX FIFO and the chip recognises it as a valid address. The Bridge's receive paths (`rx_frame_a`, `handshake_rx_a`, and their mirrors) gate on AP before draining any further bytes.


**RDA** (Receive Data Available)
: An ADLC SR2 status bit (bit 7) that is set when there is at least one unread byte in the RX FIFO. The Bridge's per-byte drain loops spin on RDA via `BIT` against the SR2 address and `BPL`/`BMI` to branch on the result.


**TDRA** (Transmit Data Register Available)
: An ADLC SR1 status bit (bit 6) that is set when the chip can accept another byte into its TX FIFO. The Bridge's per-byte transmit loops spin on TDRA via `BIT` against the SR1 address and `BVC` to branch on the result (TDRA appears in the V flag because it is bit 6).


**FV** (Frame Valid)
: An ADLC SR2 status bit (bit 1) that, at end of frame, is set if the CRC checked out and the frame arrived intact. The Bridge's receive routines check FV after draining the payload and abort via escape-to-main-loop if it is clear.
