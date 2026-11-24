# AI tool usage

The competition asks for a note on how AI tools were used. This file is kept up
to date as the project goes on.

## Milestone 1 (2026-11-23)

Claude (Anthropic, Claude Opus 5.5) was used, directed and reviewed by the author, to:

- set up the repository from the Tiny Tapeout IHP Verilog template and adapt
  Tiny Tapeout's CMOS5L SRAM example for three macros;
- write the skeleton RTL (`src/project.v`, `src/host_spi.v`, `src/sram_bb.v`)
  and the cocotb tests (`test/test.py`);
- read the three reference projects for E0-a and draft
  `docs/e0a-source-audit.md`;
- write up the ISA draft in `docs/isa-v0.md` and draft the
  milestone 1 review notes;
- extract the SRAM macro sizes and clock-to-output times from the IHP PDK files.

The architecture, the ISA and the proposal are the author's. The RTL tests were
checked to fail on a deliberately broken design (SRAM write enable tied low:
4 of 7 tests fail). Third-party files are credited where they are used
(`odb_stripes.py`, `librelane_plugin_sram_pdn.py`, `src/pdn_cfg.tcl`,
`test/sram_model/`).
