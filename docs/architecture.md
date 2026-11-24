# Architecture (milestone 1 skeleton)

The full architecture is in Proposal v5 and the ISA in [isa-v0.md](isa-v0.md).
This page describes what is in silicon-ready RTL today.

```
             ui[0..2]            +-------------------+
 host  ------------------------> |  host_spi         |  word bus (16-bit address, 16-bit data)
 (RP2350) <--------------------- |  SPI target, mode0| --------+-------------+-------------+-------------+
             uo[0] CIPO          +-------------------+         |             |             |             |
             uo[1] IRQ <---------------------------------+     v             v             v             v
                                                         |  +--------+   +--------+   +--------+   +--------+
                                                         +--|  CSRs  |   | shared |   |  SM0   |   |  SM1   |
 ui[3..7], uo[2..7], uio[0..7] <---- GPIO_OUT/OE/IN ------->|        |   |1024x16 |   | 256x16 |   | 256x16 |
                                                            +--------+   +--------+   +--------+   +--------+
                                                                         (IHP RM_IHPSG13_1P_*_c2_bm_bist macros)
```

Later milestones attach the protocol CPU (to the shared SRAM and the CSR/I-O
space), the two state machines (each to its own SRAM, read-only from the SM side)
and the bit timers and transform units (inside each SM) to the same bus.

## Pins

| Pin | Use |
| --- | --- |
| ui[0] | host SCK (≤ clk / 8, 7.5 MHz at 60 MHz) |
| ui[1] | host COPI |
| ui[2] | host CS_n |
| ui[3..7] | protocol inputs (readable in GPIO_IN) |
| uo[0] | host CIPO (0 when not in a read data phase) |
| uo[1] | host IRQ (CSR IRQ[0]) |
| uo[2..7] | protocol outputs (GPIO_OUT[5:0]) |
| uio[0..7] | protocol bidirectional (GPIO_OUT[15:8], GPIO_OE[7:0], GPIO_IN[15:8]) |

All asynchronous inputs pass through two flip-flops. rst_n is synchronised
(asynchronous assert, synchronous release).

## Host protocol

SPI mode 0, MSB first, CS_n low for the whole frame. Word addresses, 16-bit
data, auto-increment.

| Frame | Bytes on COPI | Bytes on CIPO |
| --- | --- | --- |
| WRITE | `02` `addr_hi` `addr_lo` `d0_hi` `d0_lo` `d1_hi` … | don't care (0) |
| READ | `03` `addr_hi` `addr_lo` `xx` (dummy) `xx` … | 0 for 4 bytes, then `d0_hi` `d0_lo` `d1_hi` … |

Any other opcode turns the rest of the frame into a no-op. A frame can be cut at
any point by raising CS_n; a partly shifted word is dropped.

Timing: the port samples SCK through the synchroniser, so SCK must stay high and
low for at least 4 clk cycles each. The read pipeline needs the dummy byte (8 SCK
periods, at least 64 clk cycles) to fetch the first word; it then prefetches each
next word one word ahead.

## Address map

| Word address | Size | Target |
| --- | --- | --- |
| 0x0000–0x03FF | 1024 | shared SRAM (CPU program, data, frame buffers) |
| 0x1000–0x10FF | 256 | SM0 program SRAM |
| 0x1100–0x11FF | 256 | SM1 program SRAM |
| 0x8000–0x8007 | 8 | CSRs |
| other | | reads 0, writes ignored |

| CSR | Address | Access | Contents |
| --- | --- | --- | --- |
| ID | 0x8000 | RO | 0xB175 |
| VERSION | 0x8001 | RO | 0x0001 (milestone 1) |
| SCRATCH | 0x8002 | RW | scratch |
| GPIO_OUT | 0x8003 | RW | [5:0] → uo[7:2]; [15:8] → uio_out[7:0] |
| GPIO_OE | 0x8004 | RW | [7:0] → uio_oe[7:0] |
| GPIO_IN | 0x8005 | RO | {uio_in, ui_in}, synchronised |
| IRQ | 0x8006 | RW | [0] drives the host IRQ pin |
| CYCLES | 0x8007 | RO | free-running 16-bit cycle counter |

## Memory timing

The bus request, address and write data are registered. A macro samples them on
the next rising edge; its output is valid during the following cycle and is
registered into the read-return path on the edge after that. Host-visible read
latency is three cycles, well inside the dummy byte.

| Macro | A_CLK → A_DOUT, slow corner (1.08 V, 125 °C) |
| --- | --- |
| RM_IHPSG13_1P_256x16_c2_bm_bist | 5.0 ns |
| RM_IHPSG13_1P_1024x16_c2_bm_bist | 7.1 ns |

The flow constrains the design at 60 MHz (CLOCK_PERIOD 16.667 ns).

## Floorplan and power

8×4 tiles: 1724.16 × 710.64 µm. The three macros sit side by side along the
bottom edge, flipped (FS) so their pins face the logic above them:

| Instance | Macro | Location (µm) | Size (µm) |
| --- | --- | --- | --- |
| u_mem_shared | RM_IHPSG13_1P_1024x16_c2_bm_bist | (3.36, 3.78) | 236.80 × 336.46 |
| u_mem_sm0 | RM_IHPSG13_1P_256x16_c2_bm_bist | (273.12, 3.78) | 236.80 × 118.78 |
| u_mem_sm1 | RM_IHPSG13_1P_256x16_c2_bm_bist | (542.88, 3.78) | 236.80 × 118.78 |

On SG13CMOS5L the tile's power grid is vertical Metal4 stripes only (TopMetal1
belongs to the chip-level grid), and the macros' power pins (`VDD!`,
`VDDARRAY!`, `VSS!`) are vertical Metal4 columns 11.24 µm apart. pdngen cannot
connect them on its own. The integration follows Tiny Tapeout's
[ttihp-cmos5l-sram-example](https://github.com/ttcodebot/ttihp-cmos5l-sram-example)
(adapted from Ken Pettit's
[ihp-um-janestreet-prism](https://github.com/kdp1965/ihp-um-janestreet-prism)):

1. The PDN stripe pitch is 44.96 µm (4 × 11.24), with VPWR/VGND 5.62 µm apart and
   offset 6.15 µm, so the stripes land on the macros' power columns when a macro
   sits at x = 3.36 + n × 11.24 µm. All three locations use n a multiple of 4,
   so every macro is on the tile's own stripe grid.
2. `src/pdn_cfg.tcl` is LibreLane's PDN script without the per-macro grid.
3. `Project.ExtendPowerStripes` (`librelane_plugin_sram_pdn.py`, `odb_stripes.py`)
   runs after `OpenROAD.GeneratePDN`, moves the stripes crossing each macro onto
   its columns, adds a stripe pair on every other column pair of the bit-cell
   arrays, and leaves one full-height box per stripe for the precheck's pin check.

After each hardening run, check that the macros are powered: the
`*-project-extendpowerstripes` log lists the stripes per macro, LVS must match,
and `runs/wokwi/*-openroad-irdropreport/irdrop.rpt` must report every VPWR and
VGND shape connected.

The three macros cover 135,928 µm², 11.1% of the 1.225 mm² die. Standard cells
get everything above them (370 µm above the 1024×16 macro, 588 µm above the
256×16 pair) and the right 944 µm of the die.

## Verification in milestone 1

| Check | Where | Status |
| --- | --- | --- |
| RTL simulation, 7 cocotb tests (host protocol, CSRs, all three SRAMs, GPIO, IRQ) | `test/`, `test` workflow | passing locally (Icarus 12, cocotb 2.0.1) |
| Verilator lint (`-Wall`) | local | clean |
| Hardening, LVS, DRC, precheck | `gds` workflow | see [milestones.md](milestones.md) |
| Gate-level simulation (same tests on the routed netlist with the IHP SRAM models) | `gds` workflow, `gl_test` job | see [milestones.md](milestones.md) |
