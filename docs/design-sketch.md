# Design sketch: area budget and program sketches

Paper design: nothing here has been assembled, simulated or synthesised. The
instruction set is in [isa-v0.md](isa-v0.md).

## Area budget

The configuration of [proposal.md](proposal.md) is estimated at 27% of the die:
14% standard cells and 13% SRAM macros with halos. Area is not the binding
constraint. These are flop-count estimates; first synthesis replaces them.

### Inputs

| Input | Value | Source |
| --- | --- | --- |
| Die (8×4) | 1724.16 × 710.64 µm = 1,225,257 µm² | Tiny Tapeout `tile_sizes.yaml`, ihp-sg13cmos5l |
| Flip-flop with reset | 48.99 µm² | TT IHP project page quoting the PDK (SG13G2 cell; check the CMOS5L cell) |
| Latch | 30.84 µm² | same |
| 2:1 mux | 18.14 µm² | same |
| SRAM 1024×16 (`RM_IHPSG13_1P_1024x16_c2_bm_bist`) | 236.80 × 336.46 µm = 79,674 µm² | PDK LEF (CMOS5L links to SG13G2) |
| SRAM 512×16 | 236.80 × 191.34 µm = 45,309 µm² | same |
| SRAM 256×16 | 236.80 × 118.78 µm = 28,127 µm² | same |
| SRAM 64×16 (`RM_IHPSG13_1P_64x16_c2`, no BIST) | 236.80 × 64.36 µm = 15,240 µm² | same |

Assumptions: block area = flops × 48.99 µm² × 2.0 (logic equal to flop area; 2.5
for the CPU). Clock tree, buffers and hold fixing add 20%. Each macro gets a
10 µm halo. Placement density target 55% of the non-macro area.

### Budget

| Block | Flops | Area (µm²) | Share of die |
| --- | --- | --- | --- |
| SM control (PC, execution state) | 14 | 1,372 | 0.1% |
| SM shift registers and scratch (OSR, ISR, X, Y, bit counters) | 74 | 7,250 | 0.6% |
| SM FIFOs (4×16 TX, 4×16 RX) | 140 | 13,717 | 1.1% |
| Bit timer | 53 | 5,193 | 0.4% |
| Transform unit (polynomial, LFSR, profiles, stuff, coder) | 125 | 12,247 | 1.0% |
| Pin mapping, events, traps, timeout | 92 | 9,014 | 0.7% |
| **One state machine** | 498 | 48,793 | 4.0% |
| **Two state machines** | 996 | 97,586 | 8.0% |
| Protocol CPU | 168 | 20,575 | 1.7% |
| Host port | 60 | 5,879 | 0.5% |
| Pin multiplexer and synchronisers | 90 | 9,700 | 0.8% |
| Timers, interrupts, glue | 50 | 6,899 | 0.6% |
| Standard cells before overhead | 1,364 | 140,638 | 11.5% |
| Clock tree, buffers, hold fixing (+20%) | | 28,128 | 2.3% |
| **Standard cells** | | 168,766 | 13.8% |
| SRAM 1024×16 with halo | | 91,539 | 7.5% |
| Two SRAM 256×16 with halo | | 71,278 | 5.8% |
| **Total placed** | | 331,582 | 27.1% |

Cell area available at 55% density outside the macros is about 585,000 µm²; the
design uses 29% of it.

### What the options cost

| Option | Extra area (µm², with overhead) | Share of die |
| --- | --- | --- |
| Both transform units (already included above) | 29,393 | 2.4% |
| 32-bit datapath (+384 flops) | 45,148 | 3.7% |
| Third state machine with its 256×16 program macro | 94,191 | 7.7% |
| SM programs in two private 32×16 latch stores instead of two macros | 59,501 (replaces 71,278) | −1.0% |
| Frame buffer as 512×16 instead of 1024×16 | 54,272 (replaces 91,539) | −3.0% |

### What this means

- **The transform unit is cheap.** At about 2.4% of the die, "is the hardware
  worth its area" has an easy answer. The harder question is whether it is worth
  its verification time.
- **The E1 levels will sit within a few percent of each other in area.** The
  submission decision will rest on coverage, verdict latency, SMs used and program
  size.
- **There is room to spend.** A third state machine and a 32-bit datapath together
  would bring the total to about 38%. E2 decides, after the first hardened numbers.
- **SRAM beats latches per bit by a wide margin.** A 256×16 macro (4,096 bits) is
  smaller than 1,024 latches. The latch store is a fallback for integration risk.
- **The real unknowns are not area.** Macro power on the Metal4-only PDN
  (addressed in milestone 1, to be confirmed by LVS and IR drop in CI), routing
  around three macros, and the SM fetch path at 60 MHz.

## Program sketches

Three sketches in the ISA v0 instruction set. None has been assembled or simulated.
They test the ISA on paper and give first instruction counts.

| Protocol | State machines | SM instructions | CPU work inside the frame | RP2040 reference (E0-a) |
| --- | --- | --- | --- | --- |
| CAN, standard frames, 1 Mbps | 2 | 25 + 22 | None. ID filter, error counters and retransmit run between frames | can2040: 4 SMs, 32/32 instructions; destuffing and CRC on the CPU; ACK via a match SM on pre-computed raw bits |
| LS USB device | 1 | 25 | Token match, CRC residual check, handshake choice | Pico-PIO-USB: 3 SMs, 32 instructions; RX NRZI and destuffing in PIO; TX coding and CRC on the CPU |
| 10BASE-T TX | 1 | 16 | Copy loop from SRAM to FIFO | Pico-10BASE-T: 1 SM, 3 instructions; Manchester on the CPU, CRC-32 in the DMA sniffer |

### CAN

Configuration (both SMs). Bit timer: period 60, sample point 45 (75%), resync on
falling edges, LIMIT with CLAMP, SJW 6. SM1 uses SM0's timer. Coder NRZ. Stuffing:
threshold 5, either polarity. LFSR: polynomial 0x4599, length 15, init zeros. The
TX pin is the wired-AND of both SMs.

| Profile | LFSR | Stuff | Monitor | Used for |
| --- | --- | --- | --- | --- |
| P0 | run | on | on | SOF through data |
| P1 | hold | on | on | CRC field (shift-out or compare) |
| P2 | hold | off | on | Delimiters, EOF |
| P3 | hold | off | off | ACK slot, error flag |

Deadline check: the CRC verdict exists at the sample point of the last CRC bit.
The receiver then has the whole CRC delimiter, 60 cycles, before the ACK slot, and
spends two instructions. The CPU is not involved.

Not covered: extended identifiers, remote frames, overload frames, error-passive
behaviour, the exact position of the error flag after a CRC error, and the rule
that a transmitter resynchronises only on edges it did not cause.

### LS USB device

Configuration. Bit timer: period 40, sample point 20, hard sync on the first edge
of SYNC, then LIMIT resync on every edge. Coder: NRZI (transition on 0), pin pair
D+ and D− on two bidirectional pins. Stuffing: threshold 6, ones only. LFSR:
polynomial 0x8005, length 16, init ones, inverted output. Trap: SE0 while
receiving, vector = eop.

| Profile | LFSR | Stuff | Coder | Line | Used for |
| --- | --- | --- | --- | --- | --- |
| P0 | hold | on | on | normal | SYNC, PID, CRC shift-out |
| P1 | run | on | on | normal | Everything after the PID |
| P2 | hold | off | off | force 0 | SE0 |
| P3 | hold | off | off | idle, then release | J after EOP |

CPU handler after the EOP interrupt:

| Step | Instructions (about) |
| --- | --- |
| Pop the PID and classify it (token, data, handshake) | 6 |
| Token: pop 16 bits and compare with three precomputed words (SETUP, OUT, IN for our address and endpoint, CRC5 included) | 8 |
| Data: read LFSR_LO and compare with the CRC16 residual (0x800D, to be verified) | 3 |
| Choose ACK, NAK, STALL or a data packet from endpoint state | 6 |
| Push SYNC + PID, set X, write EXEC | 5 |
| **Total** | about 28 instructions, 60 to 75 cycles |

Deadline check: at 40 cycles per bit, a device must answer within a few bit times
of EOP and not sooner than about two, a window of roughly 80 to 300 cycles (exact
values under C5). The handler fits with a factor of four to spare.

Why FS USB is the discriminating case: at 5 cycles per bit the window is roughly
10 to 32 cycles, 4 to 12 CPU instructions. The response must be pre-armed (as
Pico-PIO-USB does): the CPU decides the answer to the next token in advance, and
the SM branches on a flag and the CRC event. That needs the CRC verdict at the
last bit, which the inline unit provides; without it the CPU must keep up with
CRC16 on every byte during the packet (one byte per 40 cycles, 20 instructions).

Not covered: bus reset and suspend detection, the low-speed keep-alive EOP, and
the minimum inter-packet delay before a handshake or data.

### 10BASE-T transmit

Configuration. Bit timer: period 3 (one half-bit), no resync. Coder: Manchester,
IEEE polarity, pin pair TX+ and TX−. Stuffing off. LFSR: polynomial 0x04C11DB7,
length 32, init ones, inverted output. Shift LSB first, autopull at 16.

| Profile | LFSR | Coder | Line | Used for |
| --- | --- | --- | --- | --- |
| P0 | hold | on | normal | Preamble, SFD, FCS shift-out |
| P1 | run | on | normal | Destination address through payload |
| P2 | hold | off | force positive | Start of idle |
| P3 | hold | off | release | Idle |

Frame buffer in SRAM, written by the host: four words of preamble and SFD
(0x5555, 0x5555, 0x5555, 0xD555), then the frame without FCS, padded to at least
60 bytes. The CPU sets X to the payload word count minus one and starts copying.

| Engine | Work per 16-bit word (96 cycles) | Load |
| --- | --- | --- |
| Transform unit | 32 Manchester symbols, 16 CRC steps | Every tick, no instructions |
| State machine | `tx 16` and `jmp` | 2 cycles of 96 |
| CPU | `ldp`, FIFO-full check, `out`, loop counter, branch | About 13 cycles of 96 |
| Host | Nothing during the frame | 1 host bit per payload bit, sent in advance at any speed |

The L0 baseline needs 2 host bits per payload bit plus a host-computed FCS, and a
frame buffer twice the size. (Pico-10BASE-T uses 4 bits of RAM per payload bit.)

Not covered: odd-length frames (one extra `tx 8`), collision detection, and the
exact start-of-idle and link-pulse timings (IEEE 802.3 clause 14).

### What the sketches found

- The ISA holds for all three. No sketch needed an instruction ISA v0 lacks.
- CAN does not fit a 32-instruction shared store; it needs 47. Private program
  memories are the right call.
- One profile table is tight for CAN: it uses all four profiles.
- `sc` and LFSR re-initialisation compete: starting a frame takes two
  instructions. A "re-initialise on entry" profile bit would save one.
- The inter-packet minimum delay has no home yet (ISA open question 6).
