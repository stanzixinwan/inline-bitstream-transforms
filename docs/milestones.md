# Milestones

From [proposal.md](proposal.md), section 9. Each milestone has one exit check.

| When | Milestone | Exit check | Status |
| --- | --- | --- | --- |
| Nov 16–23 | Skeleton + 3 SRAM macros through TT flow, hardening in CI; ISA v0 review; E0-a | Precheck green | **done** (2026-11-23) |
| Nov 24–30 | Assembler and model; E0-b; bit timer, transform unit, one SM in RTL; **E1 gate** | Level chosen | next |
| Dec 1–14 | Full RTL; co-simulation; UART/SPI/I2C pass; formal | Full-chip harden at 60 MHz | |
| Dec 15–31 | CAN, LS USB, 10BASE-T TX; FPGA regression; FS USB experiment; E2 | Dev-set matrix green | |
| Jan 1–8 | RTL freeze (Jan 4); E3 blind test; gate-level sim | Blind result recorded | |
| Jan 9–17 | Final GDS, precheck, write-up, 2 days buffer | Repo complete | |
| Jan 18, 2027 | Submission | | |

## Milestone 1

| Item | Where | Status |
| --- | --- | --- |
| Repository on the TT IHP template (8×4, SG13CMOS5L, `ttihp27a` actions) | `info.yaml`, `.github/workflows/` | done |
| Skeleton RTL: host SPI port, word bus, CSRs, GPIO | `src/project.v`, `src/host_spi.v` | done |
| 3 SRAM macros instantiated and placed (1024×16 + 2 × 256×16) | `src/project.v`, `src/config.json` | done |
| Macro power on the Metal4-only PDN | `src/pdn_cfg.tcl`, `librelane_plugin_sram_pdn.py`, `odb_stripes.py` | done (hardened, precheck passed) |
| RTL tests (7 cocotb tests) | `test/` | passing locally |
| Hardening in CI | `gds` workflow | passing |
| Precheck | `gds` workflow, `precheck` job | passing |
| Gate-level test | `gds` workflow, `gl_test` job | passing (7 tests on the routed netlist) |
| ISA v0 review | [isa-v0.md](isa-v0.md), section 7 | done (decisions in 7.1, PDK facts in 7.2, fetch timing in 7.3) |
| E0-a source audit | [e0a-source-audit.md](e0a-source-audit.md) | done; C1 and C6 need rewording, C2 holds |

### Findings that changed Proposal v5 (applied in [proposal.md](proposal.md))

1. **C1 and C6 need rewording** (see the E0-a audit). Pico-PIO-USB decodes NRZI and
   drops stuff bits in PIO on receive. Pico-10BASE-T computes CRC-32 in the RP2040
   DMA sniffer, a side-attached CRC unit, not on the CPU.
2. **The 8×4 die is 1.225 mm², not 1.00 mm².** `DIE_AREA` for 8×4 on SG13CMOS5L is
   1724.16 × 710.64 µm, because the tile pitch includes the space between tiles.
   With Appendix B's area estimate unchanged (331,582 µm²), the design is about
   27% of the die, not 33%.
3. **A 64×16 macro exists** (`RM_IHPSG13_1P_64x16_c2`, no BIST). Proposal v5 says it
   does not. It is a smaller fallback than the latch store if SM programs stay short.
4. **CMOS5L SRAM = SG13G2 SRAM.** The CMOS5L library directory is a symlink, so the
   macro sizes in Appendix B are confirmed (open item in the proposal index).
5. **Macro placement is constrained by power.** On the Metal4-only PDN a macro must
   sit at x = 3.36 + n × 11.24 µm, and stacked macros must share x.
