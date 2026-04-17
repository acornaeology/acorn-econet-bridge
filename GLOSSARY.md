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


**ADLC** (Advanced Data-Link Controller)
: The SY6854/MC6854 chip used by Acorn's Econet interface to perform the line-level HDLC framing, CRC generation, and collision detection. The Econet Bridge hardware has an ADLC for each of its two network ports.
