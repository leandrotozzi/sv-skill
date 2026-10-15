# Roadmap

Open work only. Every number and every "done" or "not doing" is in
[`history.md`](history.md); design specs and implementation plans are in
`docs/superpowers/`.

## Release (by hand)

- [ ] Make the repo public and enable Pages (the `pages` job fails until then).
- [ ] Add the PyPI trusted publisher, then push the `v0.1.0` tag
      (`release.yml` builds and publishes). Until then `uv tool install svstyle`,
      which the README and `tooling.md` give, does not work.

## svstyle

- [ ] Verible stays on `v0.0-3946`, the newest with an x86_64 macOS build.
      Move the pin on an arm64 or Linux dev machine: `v0.0-4296` already
      passes the whole suite (see `history.md`, 2026-10-15).

## Open questions

- Vendor FPGA synthesis (Vivado, Quartus): a short `synth-vivado.md`
  (BRAM/DSP inference, attributes), only if that audience is in scope.
- Timing quality: a cheap logic-depth metric (Yosys `ltp` or `sta`) in
  `grade.py`, measured before it goes into the skill.
- Formal (`sby`): reopen when assertions encode the spec (ordering,
  fairness, latency); see M16 in `history.md`.
