![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg)

# Inline Bitstream Transforms

A programmable protocol emulator ASIC for the
[Jane Street Protocol Emulator ASIC competition](https://blog.janestreet.com/protocol-emulator-asic-competition/),
on Tiny Tapeout (IHP SG13CMOS5L, 8×4 tiles, 60 MHz). Columbia FoRG / Manhattan Reasoning.

The project asks how little hardware a PIO-style I/O engine needs to run protocols
with per-bit computation (CRC, bit stuffing, line coding) entirely on-chip within
their in-frame deadlines. The design pairs two field-level state machines, each
with a bit timer and an inline transform unit, with a small 16-bit protocol CPU.

**Status:** milestone 1 complete. The skeleton (host SPI port, word bus, three
IHP SRAM macros) passes hardening, precheck and gate-level tests in CI.

## Documentation

- [Proposal](docs/proposal.md)
- [Architecture](docs/architecture.md)
- [ISA v0](docs/isa-v0.md)
- [Area budget and program sketches](docs/design-sketch.md)
- [E0-a source audit](docs/e0a-source-audit.md)
- [Milestones](docs/milestones.md)
- [AI tool usage](docs/ai-usage.md)

## Tests

```sh
pip install -r test/requirements.txt   # needs Icarus Verilog 12
cd test && make
```

The `gds` workflow hardens the design with LibreLane, runs the Tiny Tapeout
precheck and repeats the tests on the gate-level netlist.

## Credits

- [Tiny Tapeout](https://tinytapeout.com) IHP Verilog template.
- SRAM power scheme from Tiny Tapeout's
  [ttihp-cmos5l-sram-example](https://github.com/ttcodebot/ttihp-cmos5l-sram-example),
  adapted from Ken Pettit's [ihp-um-janestreet-prism](https://github.com/kdp1965/ihp-um-janestreet-prism).
- SRAM macros and models from [IHP-Open-PDK](https://github.com/IHP-GmbH/IHP-Open-PDK).

Licensed under Apache-2.0.
