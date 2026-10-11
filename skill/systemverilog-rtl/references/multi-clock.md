# More than one clock

Read this, and the rules in `rules-cdc.md`, when the design has more than
one clock, an asynchronous input, or a reset that enters a clock domain.

- **Reset synchronisers** (RST-002, RST-003): a reset entering a clock
  domain goes through a reset synchroniser, one per domain: an instance of
  `assets/sync_ff.sv` with `.d_i(1'b1)`. It sits where the reset enters the
  domain: the top level, or a block that itself spans clocks (an async
  FIFO). The synchronised reset releases a few cycles after the input, so an
  interface that accepts transfers must refuse them until then: reset
  `full`/`ready` flags to the blocking value (full = 1, ready = 0), not to
  the idle one.
- **Clock-domain crossings** (CDC-001..006): two flops for a single bit (an
  instance of `assets/sync_ff.sv`, copied next to the RTL, not rewritten),
  registered in the source domain first; never a synchroniser per bit of a
  bus -- use a handshake, Gray code or an async FIFO; crossings live in a
  module whose only job is the crossing.
- **Naming** (NAM-009): a signal outside the default clock domain carries
  its domain's prefix.
