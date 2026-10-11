# CDC rules

Generated from `rules.toml` — do not edit. Full rationale and examples:
`rules-rationale.md` (load it when a rule is questioned or a finding is unclear).

`MUST` violations fail `svstyle check`. `[fix]` marks what `svstyle fix` writes for you.

## CDC — Clock domain crossing

- **CDC-001** · MUST · Every one-bit signal crossing an asynchronous clock boundary passes through two flip-flops clocked by the destination clock, with no logic between them.
- **CDC-002** · MUST · A multi-bit value is not crossed by putting a two-flop synchroniser on each bit.
- **CDC-003** · MUST · A multi-bit crossing uses one of: consolidation to a single bit regenerated locally; an unsynchronised data bus held stable behind a synchronised enable; Gray coding for counters; or an asynchronous FIFO.
- **CDC-004** · MUST · A signal is registered in its source clock domain immediately before crossing; combinational logic does not drive a crossing directly.
- **CDC-005** · MUST · A one-bit signal crossed open-loop through a two-flop synchroniser is held for more than 1.5 destination clock periods -- three destination edges. Narrower events use a closed-loop handshake.
- **CDC-006** · SHOULD · Only the top level of a design sees more than one clock; every clock-domain crossing lives inside a module whose purpose is that crossing.
