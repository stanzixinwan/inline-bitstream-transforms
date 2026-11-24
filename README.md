![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg)

# Inline Bitstream Transforms

A programmable protocol emulator ASIC for the
[Jane Street Protocol Emulator ASIC competition](https://blog.janestreet.com/protocol-emulator-asic-competition/),
built on Tiny Tapeout (IHP SG13CMOS5L, 8×4 tiles, 60 MHz). Columbia FoRG / Manhattan Reasoning.

**Research question.** What is the minimum hardware a PIO-style programmable I/O
engine needs so that protocols requiring per-bit computation (CRC, bit stuffing,
line coding) run entirely on-chip, with the result available inside their in-frame
response deadlines? The experiment may conclude that no dedicated hardware is needed.

The planned design has four layers: a bit timer and inline transform unit per
state machine (zero instructions per bit), two field-level state machines (one
instruction per field), a 16-bit protocol CPU (in-frame decisions) and the host
(program load and frame data, between frames).

## Status: milestone 1 (skeleton)

This commit is the milestone 1 skeleton: the host SPI port, a 16-bit word bus,
control registers and the three SRAM macros of the final design, hardened in CI
through the Tiny Tapeout flow. See [docs/milestones.md](docs/milestones.md) for
what is done and what changed in the proposal.

| Document | Contents |
| --- | --- |
| [docs/proposal.md](docs/proposal.md) | **The proposal (reference version)**: research question, design, experiments, milestones |
| [docs/design-sketch.md](docs/design-sketch.md) | Area budget and CAN / LS USB / 10BASE-T TX program sketches |
| [docs/architecture.md](docs/architecture.md) | Skeleton: pins, host protocol, address map, floorplan, SRAM power |
| [docs/isa-v0.md](docs/isa-v0.md) | ISA v0 and the milestone 1 review |
| [docs/e0a-source-audit.md](docs/e0a-source-audit.md) | E0-a: what Pico-PIO-USB, can2040 and Pico-10BASE-T do in PIO vs on the CPU |
| [docs/milestones.md](docs/milestones.md) | Schedule and status |
| [docs/info.md](docs/info.md) | Tiny Tapeout datasheet page |
| [docs/ai-usage.md](docs/ai-usage.md) | AI tool usage |

## Layout

| Path | What |
| --- | --- |
| `src/project.v` | Top level (`tt_um_stanzixinwan_ibt`): bus decode, CSRs, SRAM macros |
| `src/host_spi.v` | Host port: SPI target, mode 0 |
| `src/sram_bb.v` | Black boxes of the IHP SRAM macros for synthesis and lint |
| `src/config.json` | LibreLane configuration: clock, macro placement, PDN |
| `src/pdn_cfg.tcl`, `librelane_plugin_sram_pdn.py`, `odb_stripes.py` | SRAM power on the Metal4-only PDN |
| `test/` | cocotb tests (RTL and gate level), IHP SRAM behavioural models |

## Running the tests

```sh
pip install -r test/requirements.txt   # cocotb, pytest; needs Icarus Verilog 12
cd test
make                                   # RTL
make GATES=yes                         # gate level, after copying the netlist to test/gate_level_netlist.v
```

The `gds` workflow hardens the design with LibreLane, runs the Tiny Tapeout
precheck and repeats the tests on the gate-level netlist.

## Credits

- [Tiny Tapeout](https://tinytapeout.com) IHP Verilog template (Apache-2.0).
- SRAM power scheme from Tiny Tapeout's
  [ttihp-cmos5l-sram-example](https://github.com/ttcodebot/ttihp-cmos5l-sram-example),
  adapted from Ken Pettit's [ihp-um-janestreet-prism](https://github.com/kdp1965/ihp-um-janestreet-prism)
  (Apache-2.0).
- SRAM macros and behavioural models from [IHP-Open-PDK](https://github.com/IHP-GmbH/IHP-Open-PDK) (Apache-2.0).

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper
than ever to get your digital and analog designs manufactured on a real chip.
To learn more and get started, visit https://tinytapeout.com.
