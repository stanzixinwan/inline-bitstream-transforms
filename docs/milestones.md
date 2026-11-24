# Milestones

Each milestone has one exit check.

| When | Milestone | Exit check | Status |
| --- | --- | --- | --- |
| Nov 16–23 | Skeleton + 3 SRAM macros through TT flow, hardening in CI; ISA v0 review; E0-a | Precheck green | **done** (2026-11-23) |
| Nov 24–30 | Assembler and model; E0-b; bit timer, transform unit, one SM in RTL; **E1 gate** | Level chosen | next |
| Dec 1–14 | Full RTL; co-simulation; UART/SPI/I2C pass; formal | Full-chip harden at 60 MHz | |
| Dec 15–31 | CAN, LS USB, 10BASE-T TX; FPGA regression; FS USB experiment; E2 | Dev-set matrix green | |
| Jan 1–8 | RTL freeze (Jan 4); E3 blind test; gate-level sim | Blind result recorded | |
| Jan 9–17 | Final GDS, precheck, write-up, 2 days buffer | Repo complete | |
| Jan 18, 2027 | Submission | | |

## Milestone 1 (done)

| Deliverable | Status |
| --- | --- |
| TT IHP project (SG13CMOS5L, 8×4, 60 MHz) with host SPI port, word bus, CSRs, GPIO | done |
| Three SRAM macros (1024×16 + 2 × 256×16) placed and powered on the Metal4-only PDN | done |
| Hardening, precheck and gate-level test in CI | passing |
| ISA v0 review | [isa-v0.md](isa-v0.md), section 7 |
| E0-a source audit | [e0a-source-audit.md](e0a-source-audit.md) |
