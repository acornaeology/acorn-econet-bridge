# Event-driven re-announcement: why a solo Bridge goes silent

Most periodic-broadcast protocols you've met hold some kind of timer: every thirty seconds, every two minutes, every RIP-advertisement-interval, the participant wakes up, composes an advertisement, and puts it on the wire. The Acorn Econet Bridge does not work like that. Its re-announcement behaviour is not time-driven — it is event-driven, and the event is hearing another bridge.

This turns out to be a deliberate architectural choice with several nice consequences. It also has one easily-mis-read consequence: a lone bridge, connected to two segments with no other bridges on them, will emit exactly two frames in its lifetime — its boot-time pair of BridgeReset scouts — and then never transmit again unless it is reset. That is the expected steady state, not a bug.


## The evidence

The state machine lives in four bytes of zero-page RAM at `&0229`-`&022C`:

```
announce_flag    enables the response burst; bit 7 additionally
                 selects which Econet side the next BridgeReply
                 goes out on (0 = side A, 1 = side B)
announce_tmr_lo  16-bit countdown, ticked by the main loop's
announce_tmr_hi  idle path; reaches zero -> fire
announce_count   remaining BridgeReplies in this burst
```

A full scan of the ROM shows `announce_flag` is written at exactly four sites:

| Site | Value | Location |
|---|---|---|
| `&E035` | `&00` | Inside the reset handler — clears the flag at boot. |
| `&E0C4` | `&00` | Inside `re_announce_done` — clears the flag when `announce_count` hits zero. |
| `&E1EB` | `&40` | Inside `rx_a_handle_80` — sets the flag after receiving a BridgeReset on side A. |
| `&E36C` | `&80` | Inside `rx_b_handle_80` — sets it after receiving a BridgeReset on side B. |

Every write that _sets_ the flag non-zero is a response to having received a BridgeReset (`ctrl=&80`) from another bridge. No other receive-handler touches the flag. No timer, no interrupt, no startup path sets it. The main loop's idle path reads the flag and acts on it, but never writes it.

In particular, receiving a BridgeReply (`ctrl=&81`) — the re-announcement message type that peers send in their own response bursts — does _not_ set `announce_flag`. The `rx_?_handle_81` handler starts at `LDY #6` and immediately enters the payload-learn loop, without touching the flag.


## What the protocol looks like in action

Put those observations together and a handful of scenarios fall out cleanly.

### Solo bridge, cold boot

```
t=0    Bridge A boots. Reset handler runs. build_announce_b builds
       a BridgeReset (ctrl=&80) template. wait_adlc_a_idle + 
       transmit_frame_a emits it on side A. tx_data0 is patched to
       net_num_a. wait_adlc_b_idle + transmit_frame_b emits it on
       side B.

t~0    Reset falls into main_loop. Both ADLCs are re-armed. The
       poll loop starts. announce_flag is 0 (cleared at &E035).

t→∞    No peers exist. No frames arrive. main_loop_idle spins
       forever with announce_flag = 0, so the idle path never
       advances past the `LDA announce_flag / BEQ` at &E089. The
       Bridge emits nothing further.
```

Total lifetime traffic: two frames.

### Two bridges, cold boot

```
t=0    Both bridges power up, each sends its pair of BridgeReset
       scouts. Each bridge's side A and side B see each other's
       BridgeReset.

t~ε    Each bridge's rx_?_handle_80 fires. init_reachable_nets
       wipes the routing tables. announce_flag is set to &40 or
       &80 depending on which side the BridgeReset was heard on.
       announce_tmr is seeded with the opposite side's net_num
       as the high byte. announce_count = 10.

t~ε+   main_loop_idle sees announce_flag non-zero and starts
       decrementing announce_tmr. After ~&8000 idle iterations,
       the timer expires. re_announce runs: builds a template,
       patches ctrl to &81, transmits a BridgeReply on the
       selected side, decrements announce_count, re-arms the
       timer to &8000.

       Each bridge hears the other's BridgeReply, learns routes
       from it, but does NOT schedule another burst. The
       handle_81 path learns and forwards but doesn't touch
       announce_flag.

t=end  Each bridge's announce_count reaches zero. re_announce_done
       clears announce_flag. Both bridges fall silent.
```

Total lifetime traffic: two BridgeReset frames from each bridge, then ten BridgeReply frames from each, then nothing. Twenty-two frames total, bounded by the count, regardless of how long the bridges stay up.

### A third bridge joining an established mesh

```
t=0    Bridges A and B have been up for some time. announce_flag
       is 0 on both; they're silent. reachable_via_? tables
       reflect the topology they learned during their boot
       exchange.

t=T    Bridge C is powered on. It emits BridgeReset on each side.
       Bridge A hears it (on whichever side shares a segment).
       Bridge A's rx_?_handle_80 fires: wipes reachable_via_?,
       schedules 10 BridgeReplies.

t~T    Same for Bridge B if it too shares a segment with C.

t>T    Each of A, B, and C emits its burst. Each hears the
       others'. Everyone re-learns the topology, including
       Bridge C.

t=end  All counters reach zero, everyone clears their flags, all
       three bridges fall silent again.
```

The new bridge's arrival is the event that triggers a re-learning cascade, exactly when re-learning is needed.


## Why it works

The design is conservative in a way that's easy to miss if you expect periodic advertising:

1. **Bandwidth is bounded by topology events**, not by elapsed time. No matter how long bridges stay up, they don't generate announcement traffic beyond the ten-message burst triggered by each BridgeReset. A long-running network with stable topology sees zero bridge-protocol traffic.

2. **No heartbeat means no clock skew**. There's nothing to synchronise, nothing to keep bridges from drifting apart in phase. The stagger delays in `stagger_delay` and in `announce_tmr`'s seeding from the local network number are defence against collisions within a single burst, not maintenance of a shared cadence.

3. **Stale routes persist but don't cause harm.** `reachable_via_?` entries set by a past learning burst stay put until the next BridgeReset. If a bridge goes offline without announcing, the others continue to think they can route through it. Frames addressed to the now-unreachable network will be forwarded to the dead bridge's segment and simply go unanswered at the other end's handshake — the standard Econet four-way timeout catches the failure at the endpoint, not the bridge.

4. **Adding a bridge is self-healing.** A new bridge boots with empty `reachable_via_?` tables. Its BridgeReset triggers every other bridge to wipe and re-learn. Within one burst period, the new topology has propagated, and everyone goes quiet.

5. **BridgeReply doesn't cascade.** Because `handle_81` does not set `announce_flag`, a bridge receiving a peer's re-announcement doesn't generate a counter-burst of its own. This is important: if BridgeReplies _did_ trigger further bursts, two bridges would keep re-announcing to each other indefinitely — a loop-forming bug. The distinction between `&80` (cascade-causing) and `&81` (learning-only) is what breaks the loop.


## What the author gave up

In exchange for the above, the Bridge gives up:

- **Discovery of silent failures.** If a bridge crashes without the chance to emit a BridgeReset, its peers won't notice. They'll forward into a black hole until the next time someone in the mesh reboots. A periodic heartbeat protocol would detect the loss at the next missed advertisement interval.

- **Dynamic load balancing.** With static routes that only change on boot events, there's no way for the mesh to adapt to congestion or rerouting preferences at runtime. Acorn Econet wasn't trying to be that kind of network.

- **Detection of late-joining stations.** Because routing is by network number, not station number, a station appearing on an already-known network does require announcement. The Bridge doesn't care about individual stations — it only routes between networks, and networks don't tend to appear and disappear the way stations do.

For a workgroup local-area network with a dozen bridges at most, operating over cable lengths measured in hundreds of metres, these trade-offs are eminently defensible. The result is a protocol that mostly isn't there — silent by default, chatty only when something has actually happened. That is the kind of network I would rather debug.


## The finding in one sentence

**Receiving a BridgeReset is the only event in the Bridge's entire firmware that can cause it to start re-announcing**, which means that a bridge with no peers never has anything to respond to, which means that a lone bridge emits two frames in its lifetime and then sits silent until reset.


## Cross-references

- `announce_flag` / `announce_tmr_lo/hi` / `announce_count` label header at the top of the driver script — documents the whole state machine.
- `rx_a_handle_80` at `&E1D6` and `rx_b_handle_80` at `&E357` — the only two routines that set the flag.
- `re_announce` at `&E098` — the action that runs when the flag is set and the timer fires.
- `re_announce_done` at `&E0C2` — clears the flag when the burst is complete.
- [The Bridge architecture overview](bridge-architecture-overview.md) — context.
- [One frame, two broadcasts](two-broadcasts-one-template.md) — the boot-time dual-broadcast of BridgeReset that's the _only_ unprompted announcement a bridge ever emits.
