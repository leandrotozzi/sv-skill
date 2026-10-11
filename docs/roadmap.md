# Roadmap

Open work only. Every number and every "done" or "not doing" is in
[`history.md`](history.md); design specs and implementation plans are in
`docs/superpowers/`.

## Release (by hand)

- [ ] Make the repo public and enable Pages (the `pages` job fails until then).
- [ ] Add the PyPI trusted publisher, then push the `v0.1.0` tag
      (`release.yml` builds and publishes). Until then `uv tool install svstyle`,
      which the README and `tooling.md` give, does not work.

## Cost

- [ ] With the skill, VerilogEval costs 3.5× per problem for equal pass@1:
      about 40 % testbench, 40 % reading the skill, 20 % the check/fix loop.
      Measure a "write, one `fix`, one `check`, leave SHOULDs" protocol with
      `evals/run.py`; round 11 closed the style with one `fix` in 5/5.

## svstyle

- [ ] `fix` speed: the difflib alignment in the token invariant is about a
      third of `fix`, and `parse` runs several times per pass.
- [ ] A single comment above two declarations leaves the second with a
      `TODO: describe` (no mechanical fix without inventing text).
- [ ] LNG-001 reports a closing `` `default_nettype wire`` as a `wire`
      declaration (MUST), and `fix` then appends `` `resetall`` on the same
      line (it compiles, but reads badly).
- [ ] Verible stays on `v0.0-3946`; move the pin when the non-blocking
      `verible-latest` CI job is green.

## Skill

- [ ] `ASSERT` covers a reset pulse between edges for one-cycle properties
      only; `##2` and longer stay exposed.
- [ ] Skipping the testbench on small blocks leaves rr-arbiter's fairness
      and order unchecked (its planted bugs were caught 3/3 before).

## Open questions

- Vendor FPGA synthesis (Vivado, Quartus): a short `synth-vivado.md`
  (BRAM/DSP inference, attributes), only if that audience is in scope.
- Timing quality: a cheap logic-depth metric (Yosys `ltp` or `sta`) in
  `grade.py`, measured before it goes into the skill.
- Formal (`sby`): reopen when assertions encode the spec (ordering,
  fairness, latency); see M16 in `history.md`.
