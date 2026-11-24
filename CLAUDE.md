# Notes for Claude

This repository is the source of truth for the project. When a doc here and a
Claude Doc, project note or past chat disagree, this repository wins.

- Proposal: `docs/proposal.md` (replaces Proposal v5). ISA: `docs/isa-v0.md`.
  Area budget and program sketches: `docs/design-sketch.md`.
- Status and next steps: `docs/milestones.md`. Update it when a milestone item
  changes state.
- Competition rules: https://blog.janestreet.com/protocol-emulator-asic-competition/
  (deadline 2027-01-18; TT IHP SG13CMOS5L, 8x4 tiles; write-up weighs heavily).
- Keep `docs/ai-usage.md` up to date; the competition requires it.

Build and test:

- RTL tests: `cd test && make` (Icarus Verilog 12, cocotb 2.0.1).
- Hardening, precheck and gate-level tests run in the `gds` GitHub workflow
  (LibreLane, `TinyTapeout/tt-gds-action@ttihp27a`, pdk `ihp-sg13cmos5l`).
- SRAM macros: instance names in `src/project.v` must match `MACROS` and
  `PDN_MACRO_CONNECTIONS` in `src/config.json`. Macros sit at
  x = 3.36 + n x 11.24 um (Metal4-only PDN, see `docs/architecture.md`).
