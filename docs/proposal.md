# Inline Bitstream Transforms — Proposal

Design proposal for the Jane Street Protocol Emulator ASIC Competition. This file is
the reference version; it replaces Proposal v5 (Claude Doc, 2026-11-16). The ISA is in
[isa-v0.md](isa-v0.md); the area budget and program sketches are in
[design-sketch.md](design-sketch.md). The change log is at the end.

> **Research question.** What is the *minimum* hardware a PIO-style programmable I/O
> engine needs so that protocols requiring per-bit computation (CRC, bit stuffing,
> line coding) run entirely on-chip, with the result available inside their in-frame
> response deadlines? The experiment may conclude that no dedicated hardware is needed.

## 1. Problem

PIO-style engines (RP2040 PIO) are cycle-exact but cannot compute per bit, so real
implementations push CRC, stuffing and most line coding to a companion CPU, and meet
in-frame deadlines by computing the answer before the frame ends (E0-a). CPU-style
cores (TI PRU) can compute, but per-bit work eats most of a small cycle budget. A
~1 mm² emulator chip has no large companion CPU; the only other compute is a host
behind a slow port. Whether that matters depends on the workload:

| Class | Examples (cycles/bit at 60 MHz) | In-frame deadline | Host can do per-bit work? | What dedicated hardware buys |
| --- | --- | --- | --- | --- |
| A. Low rate, deadline | CAN 1 Mbps (60), LS USB (40) | CAN ACK ~1 bit after CRC; USB handshake a few bits after EOP | No, on receive | Headroom (a small CPU is expected to suffice) |
| B. High rate, no deadline | 10BASE-T TX (6) | None | Yes, by precomputing CRC and Manchester | Host bandwidth and buffer, not feasibility |
| C. High rate, deadline | FS USB device (5), 10BASE-T RX (6) | FS USB: ~10–32 cycles | No, data is live | Feasibility for a ~30 MIPS CPU: the discriminating class |

For class C the binding resource is CPU throughput *during* the frame (CRC and
destuffing per byte), not the handshake decision itself, which can be pre-armed. An
RP2040 at 120 MHz or more does FS USB device in software (Pico-PIO-USB, E0-a); our
protocol CPU runs at about 30 MIPS.

## 2. Design

| Layer | Runs | Deadline |
| --- | --- | --- |
| **Bit timer + inline transform unit** (one per SM) | Bit timing with edge resync; CRC, stuffing, NRZI/Manchester; zero instructions per bit | Every bit, down to 3 cycles per half-bit |
| **Field-level state machines** (2) | Field boundaries, stage selection, pins, raw waveforms | One instruction per field |
| **Protocol CPU** (16 bit, shared) | PID/ID match, toggles, ACK/NAK choice, checksums, SRAM↔FIFO | Within the frame |
| **Host** (RP2350 on the demo board) | Program load, descriptors, frame data, logging | Between frames |

Concurrency: two single-SM protocols, or one two-SM protocol (CAN).

**Transform primitives**, all configuration, no per-protocol logic: bit timer (period,
sample point, hard/limited resync); LFSR up to 32 bit (CRC-5/8/15/16/32, PRBS; length
1 = parity); run-length counter (CAN/USB stuffing, HDLC); transition coder (NRZI,
Manchester, biphase); bit monitor (CAN arbitration, I2C multi-master). TX order:
shift → LFSR → stuff → coder → pin; RX is the reverse.

**Bit-boundary control (the contribution).** A bit boundary is a bit-timer tick.

- `tx n` / `rx n` move n *payload* bits; the SM spends one instruction per field.
  Stuff bits are invisible to the count.
- A 3-bit field on each instruction selects one of four firmware-defined stage
  profiles, effective from that field's first bit.
- The CRC remainder shifts out through stuffing and coding; on RX it is compared
  serially, so the verdict exists at the last bit's sample point.
- Stuff, CRC, coder and monitor violations are events for `jmp`, `wait`, CPU
  interrupts and one-cycle traps.

**Targets.** Required: UART, SPI modes 0–3, I2C 100/400 kHz. Silicon: CAN, LS USB
device, 10BASE-T TX (argued as host-bandwidth saving). Discriminating experiment,
model and FPGA only: FS USB device handshake.

## 3. Novelty and prior art

The primitives and their inline placement are not new: Intel 8044 and Zilog Z8530 do
CRC, NRZI/FM and zero insertion inline; STM32 has programmable CRC; TI PRU-ICSSG has a
side-attached CRC accelerator; the RP2040 DMA sniffer computes CRC-32 on the fly and is
used that way for 10BASE-T TX (E0-a). Our claims concern attaching such a stage to a
cycle-exact programmable core:

1. **Bit-boundary control.** Firmware-defined stage profiles switch on exact bit
   boundaries, with stuffing-aware counting, CRC shift-out and compare, and one-bit
   event response.
2. **Zero verdict latency without pre-computation.** CRC and framing validity are
   ready at the last bit. A side-attached accelerator needs a word flush first;
   software reaches the same latency only by pre-computing the expected raw bits and
   spending a state machine on the compare, as can2040 does for the CAN ACK.
3. **Method.** Minimum hardware derived from per-protocol deadline budgets, reported
   as an area–coverage frontier.

## 4. Evidence so far

| ID | Claim | Confidence | Validated by |
| --- | --- | --- | --- |
| C1 | can2040 does destuffing, stuffing and CRC on the CPU. Pico-PIO-USB decodes NRZI and drops stuff bits in PIO on receive but does not check stuff errors; TX NRZI, stuffing and both CRCs run on the CPU | High (source read) | E0-a ✓ |
| C2 | can2040 uses 32/32 PIO instructions and 4/4 SMs; Pico-PIO-USB uses 32 instructions over two PIO blocks (27/32 in the RX block) and 3 SMs | High (source read) | E0-a ✓ |
| C3 | PRU-style core at 60 MHz: CAN 53%, LS USB 78% of budget; transforms are 1/3–1/2 of it (target rates to be fixed) | Low | E0-b |
| C4 | A CPU-style core cannot do 10BASE-T (183%) | Low | E0-b |
| C5 | CAN ACK and USB handshake windows rule out host round trips | High (values to cite) | Spec lookup |
| C6 | Pico-10BASE-T computes Manchester on the CPU (table) and CRC-32 in the RP2040 DMA sniffer, a side-attached unit; 4 host bits per payload bit | High (source read) | E0-a ✓ |
| C7 | Design ≈ 27% of the 1.225 mm² die; both transform units ≈ 2.4% | Low-medium | First synthesis |
| C8 | CAN: 2 SMs, ~47 instructions; LS USB: 1 SM, ~25; 10BASE-T TX: 1 SM, ~16 | Low-medium | Assembler and model |
| C9 | Software meets in-frame deadlines by pre-computation: pre-armed USB handshakes; can2040's match SM compares pre-computed raw CRC bits and injects the ACK | High (source read) | E0-a ✓ |

## 5. Experiments

- **E0.** (a) Done, see [e0a-source-audit.md](e0a-source-audit.md). (b) Write CAN, LS
  USB, SPI for L0 in the cycle-accurate model and replace C3/C4 with worst-case cycles
  per bit. (c) If transforms are under 20% of the cost, pivot to concurrency and
  headroom.
- **E1 (decision by Nov 30).** Compare L0 (base only, host precompute allowed), L1
  (base + side-attached serial LFSR + bit-manipulation CPU instructions), L2 (base +
  inline unit) on CAN, LS USB, 10BASE-T TX, FS USB. Metrics: occupancy (pass ≤ 70%),
  verdict latency, host bits per line bit, area, program size, SMs used. L0 and L1 are
  fully optimised and may use every pre-computation trick found in E0-a (pre-armed
  handshakes, a compare SM on pre-computed raw bits); the SMs those tricks consume
  count against them.
- **E2.** Ablate CRC, stuffing, coding, monitor stages on the development set (UART,
  SPI, I2C, CAN, LS USB, 10BASE-T TX); sweep SM count, datapath width, FIFO depth.
  Pick the smallest config that covers the set.
- **E3 (blind test).** After RTL freeze, an independent evaluator names a new
  protocol; we implement it with programs and configuration only. HDLC, LIN, MDIO,
  1-Wire, DALI are supplementary.

**Pre-registered decisions:**

| Observation | Decision |
| --- | --- |
| L0 meets every target, including FS USB | No transform hardware; headline the bit timer and field sequencing |
| L1 meets everything L2 does, within every deadline | Submit L1 |
| L2 meets FS USB and L1 does not, or L2 frees an SM L1 needs | Submit L2 |
| Tie on coverage, L2 cuts host bits or program size substantially | Submit L2, claim headroom only |
| Bit timing dominates every level | Report it; bit timer becomes the headline |

## 6. Verification

1. UART, SPI (controller and target), I2C (with clock stretching) pass in RTL
   simulation first.
2. Formal (SymbiYosys): LFSR equals polynomial division; stuff/destuff are inverses;
   profiles switch exactly on a field's first boundary; bit-timer tick spacing.
3. cocotb co-simulation of the Python model against RTL, cycle by cycle.
4. Fault injection: CRC and stuff errors, CAN arbitration loss and error frames, clock
   offset sweeps (±0.5%, ±1.5%), jitter.
5. Whole-chip gate-level simulation: program load, UART, SPI, I2C, one CAN frame.
   Runs in CI on every push from milestone 1 (`gds` workflow, `gl_test` job).
6. FPGA regression on the FoRG / Manhattan Reasoning cloud platform against
   open-source reference peers; real-device interop (PC USB, CAN adapter, NIC) on a
   local board.

## 7. Platform decisions

They are reversible engineering choices. The research variable remains the
transform-hardware level (E1).

| Decision | Choice | Reason |
| --- | --- | --- |
| State machines | 2 (a parameter) | A third costs ~7.7% of die; kept at 2 to bound verification |
| Protocol CPU | 16 bit, 8 registers, 2 cycles/instruction | In-frame decisions; ~1.7% of die |
| Memory | Shared 1024×16 SRAM (CPU program, data, frame buffer); private 256×16 SRAM per SM | Smallest BIST-equipped 16-bit macros that fit; fallback 64×16 macro (`RM_IHPSG13_1P_64x16_c2`) or latch store |
| Macro placement | Side by side on the bottom edge at x = 3.36 + n × 11.24 µm | The CMOS5L tile PDN is Metal4 stripes only; stripes must land on the macros' Metal4 power columns |
| Datapath | 16 bit; LFSR 32 bit | Matches CPU and SRAM width; 32 bit would add ~3.7% |
| FIFO | 4×16 TX + RX per SM | 96 cycles per word at 10 Mbps; CPU refills in ~10 |
| Clock | 60 MHz | Confirmed by Tiny Tapeout; 3 cycles per 10BASE-T half-bit. SRAM clk→Q (slow corner) 5.0 ns (256×16), 7.1 ns (1024×16) |
| Host port | SPI target mode 0 + IRQ: SCK ui[0], COPI ui[1], CS_n ui[2], CIPO uo[0], IRQ uo[1]; SCK ≤ 7.5 MHz | Leaves 5 in, 6 out, 8 bidirectional pins |
| Input sync | 2-flop | Cost held fixed across E1 levels |

## 8. Deliverables

Public repository: RTL on the TT IHP template (8×4) with GDS passing precheck; cocotb,
formal and gate-level tests; architecture and ISA documentation; assembler,
cycle-accurate simulator and example programs (UART, SPI, I2C, CAN, LS USB,
10BASE-T TX, blind-test protocol); verification report with FPGA regression matrix;
AI-usage note; optional demo video.

## 9. Milestones

Status per item is in [milestones.md](milestones.md).

| When | Milestone | Exit check |
| --- | --- | --- |
| Nov 16–23 | Skeleton + 3 SRAM macros through TT flow, hardening in CI; ISA v0 review; E0-a | Precheck green |
| Nov 24–30 | Assembler and model; E0-b; bit timer, transform unit, one SM in RTL; **E1 gate** | Level chosen |
| Dec 1–14 | Full RTL; co-simulation; UART/SPI/I2C pass; formal | Full-chip harden at 60 MHz |
| Dec 15–31 | CAN, LS USB, 10BASE-T TX; FPGA regression; FS USB experiment; E2 | Dev-set matrix green |
| Jan 1–8 | RTL freeze (Jan 4); E3 blind test; gate-level sim | Blind result recorded |
| Jan 9–17 | Final GDS, precheck, write-up, 2 days buffer | Repo complete |
| Jan 18, 2027 | Submission | |

## 10. Key risks

- **L1 matches L2.** Mitigation: verdict-latency metric, FS USB case, pre-registered
  rule to submit L1 on a tie. E0-a shows L0/L1 can reach zero verdict latency by
  pre-computation; the honest metric is the SMs and CPU time that costs.
- **Headline case not on silicon.** FS USB is model and FPGA only; say so plainly.
- **SRAM macro power on the Metal4-only PDN.** Mitigation: the ExtendPowerStripes
  scheme from Tiny Tapeout's CMOS5L SRAM example, hardened in CI from milestone 1;
  not yet proven in silicon by anyone. Fallback: 64×16 macros or latch store.
- **Bit-timer generality** across CAN, USB, UART, Manchester. Mitigation: formal
  properties and offset sweeps.
- **10BASE-T TX waveform** (pad delay, P/N skew at 50 ns half-bit). Mitigation: FPGA
  validation in December.
- **Schedule.** If a milestone slips a week, cut in this order: 10BASE-T RX, FS USB,
  10BASE-T TX, CAN.
- **"PIO plus a CRC block".** Mitigation: lead with bit-boundary control, cite
  Z8530-class prior art and the RP2040 DMA sniffer, back it with E1 and the blind
  test.

## Change log

**2026-11-23 (repository version, after milestone 1).** Changes from Proposal v5:

1. C1, C2, C6 rewritten from the E0-a source audit; new claim C9 (deadlines met by
   pre-computation).
2. Class C reframed: the binding resource is in-frame CPU throughput; RP2040 does FS
   USB device in software at 120 MHz or more.
3. Novelty claim 2 now says what software needs to match zero verdict latency; the
   RP2040 DMA sniffer added to prior art.
4. E1: L0/L1 may use E0-a's pre-computation tricks; SMs used is a metric.
5. Die is 1.225 mm² (8×4 `DIE_AREA` 1724.16 × 710.64 µm), not 1.00 mm². All area
   shares recomputed: design 27%, transform units 2.4%, third SM 7.7%, 32-bit
   datapath 3.7%, CPU 1.7%.
6. PDK facts: CMOS5L SRAM is the SG13G2 SRAM (symlink), sizes confirmed; a 64×16
   macro exists; SRAM clock-to-output times added.
7. Platform: macro placement rule and host pin order added.
8. Milestone 1 runs to Nov 23; milestone 2 starts Nov 24.

**2026-11-16 (v5).** See the v5 Claude Doc for changes from v4.
