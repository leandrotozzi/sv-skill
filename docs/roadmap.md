# Roadmap

Open work only. Every number and every "done" or "not doing" is in
[`history.md`](history.md).

## Open questions

- Vendor FPGA synthesis (Vivado, Quartus): a short `synth-vivado.md`
  (BRAM/DSP inference, attributes), only if that audience is in scope.
- Timing quality: `grade.py` records logic depth and transistors (see
  `docs/research/timing-metric.md`). Measure the classics with and
  without the skill, three runs each, before anything goes into the skill.
- Formal (`sby`): reopen when assertions encode the spec (ordering,
  fairness, latency); see M16 in `history.md`.
