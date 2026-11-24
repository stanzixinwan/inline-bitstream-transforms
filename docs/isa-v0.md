# ISA v0

Draft for review, not a frozen spec. Sections 1–6 have not been assembled or
simulated yet; the assembler and cycle-accurate model come in milestone 2.
Section 7 records what the skeleton RTL and the PDK data settled.

## 1. Timing model

- The clock is 60 MHz. A state machine (SM) executes one instruction per cycle
  unless the instruction blocks.
- Each SM has a **bit timer**: a prescaled counter running 0 to PERIOD−1. A
  **tick** is the wrap to 0. The **sample point** is the cycle where the counter
  equals SAMPLE. A bit boundary is a tick.
- TX: on each tick, an active `tx` field pushes one symbol through
  LFSR → stuff → coder → pin. With no active field, the pin holds the current
  profile's line state and UNDERRUN is set if a field was expected.
- RX: on each sample point, an active `rx` field takes one sample through
  coder → destuff → LFSR → ISR.
- Blocking: `tx n` returns when its last payload bit has entered the pipeline.
  `rx n` returns when its n-th payload bit has been sampled. The SM then has one
  full bit time to issue the next field: at least 3 cycles at the 10BASE-T
  half-bit rate, 6 per Manchester payload bit.
- Stage control: the profile named by an instruction applies from the first bit
  boundary of that instruction's field. On a non-field instruction it applies at
  the next boundary.
- Events are registered. They are visible to `jmp`, `wait` and traps one cycle
  after the boundary that caused them.
- Resync on the configured edge of the synchronised input, with phase error *e*
  relative to the nearest tick. HARD: the edge becomes the tick. LIMIT: move by
  *e* if |*e*| ≤ SJW; otherwise move by SJW (CLAMP, for CAN) or ignore the edge
  (IGNORE, for Manchester data edges).

## 2. State machine

Per SM: PC (8 bit), OSR and ISR (16 bit), X and Y (16 bit), TX and RX FIFOs
(4×16 each), bit timer, transform unit, 16 sticky event flags, trap vector and
mask. Program memory: a private 256×16 SRAM.

Instruction word (16 bit): 2-bit w, 3-bit sc, 3-bit op, 8-bit arg. The sketch does
not fix the bit order; `w[15:14] sc[13:11] op[10:8] arg[7:0]` is the proposed
order for the assembler.

| Field | Values |
| --- | --- |
| w (wait before executing) | 00 now; 01 at next tick; 10 at next sample point; 11 reserved |
| sc (stage control) | 0 keep; 1–4 select profile P0–P3; 5 re-initialise the LFSR; 6 clear transform events; 7 reserved |

| op | Mnemonic | arg layout | Meaning |
| --- | --- | --- | --- |
| 0 | `jmp cond, addr` | addr[7:0] | cond: always; X=0; X≠0 then decrement; Y≠0 then decrement; pin high; event A; event B; X≠Y. Events A and B are chosen by JMPSEL. With w=sample, the pin is tested at the sample point. |
| 1 | `wait pol, src, idx` | pol[7] src[6:5] idx[4:0] | Block until a pin, event or peer-SM flag has the given polarity. If TOUT is nonzero and that many ticks pass, set TIMEOUT. |
| 2 | `tx n, src` | nb[7] src[6:5] n−1[4:0] | Send n payload bits. src: OSR; LFSR remainder (CRC shift-out); zeros; ones. nb=1 does not block. |
| 3 | `rx n, dst` | nb[7] dst[6:5] n−1[4:0] | Receive n payload bits. dst: ISR; discard; compare with LFSR remainder (sets CRC_ERR on mismatch); compare with OSR (sets MISMATCH). |
| 4 | `set dst, v` | dst[7:5] v[4:0] | dst: pins; pin directions; X; Y; raise CPU IRQ v; set or clear peer flag v. |
| 5 | `mov dst, src` | dst[7:4] src[3:0] | X, Y, OSR, ISR, FIFO (pull or push, blocking), LFSR low, LFSR high, pins, status, zero. |
| 6 | `dly n` | n−1[7:0] | Wait n cycles (1–256), for cycle-exact waveforms without the bit timer. |
| 7 | `ctl sub, v` | sub[7:5] v[4:0] | nop (carries sc only); set direction TX or RX; bit timer run, stop, arm hard sync, clock-out on or off; trap enable or disable. |

Stage profile (one byte each, P0–P3, written by the CPU or the host):

| Bits | Meaning |
| --- | --- |
| 0 | LFSR runs on payload bits (0 = hold) |
| 1 | Run-length stage on (stuff on TX, destuff and check on RX) |
| 2 | Coder on (0 = NRZ pass-through) |
| 3 | Bit monitor on (driven bit compared with sampled bit; sets MISMATCH) |
| 5:4 | Line override: none; force 0 (SE0 on a pin pair); force idle; release (high-Z) |
| 6 | Events in TRAPMASK may trap while this profile is active |
| 7 | Reserved |

Events: STUFF_ERR, CRC_ERR, CODE_VIOL, SE0, MISMATCH, TIMEOUT, UNDERRUN,
OVERRUN, EDGE, TXDONE, FIFO level, two peer-SM flags, two CPU flags, one
reserved. A trap aborts the current instruction, forces the line to idle,
latches the cause and PC, and sets PC to TRAPVEC.

## 3. I/O registers (SM0 at 0x00, SM1 at 0x40, global at 0x80)

| Offset | Register | Contents |
| --- | --- | --- |
| 0x00 | CTRL | Enable, direction, restart |
| 0x01 | EXEC | Write: execute this instruction now (the CPU steers the SM with a `jmp`) |
| 0x02–0x04 | TXFIFO, RXFIFO, FSTAT | Push, pop, levels |
| 0x05–0x06 | X, Y | Scratch |
| 0x07–0x09 | BT_PERIOD, BT_SAMPLE, BT_CFG | Period (12 bit), sample offset, prescaler, resync edge and mode, SJW, clock-out pin, timebase select (own timer or the other SM's) |
| 0x0A–0x0D | POLY_LO/HI, LFSR_LO/HI | Polynomial; LFSR state (readable, so the CPU can check a residual) |
| 0x0E | XF_CFG | CRC length, init, output inversion; stuff threshold and mode; coder mode; pin pair |
| 0x0F–0x10 | PROF01, PROF23 | Stage profiles |
| 0x11–0x13 | EV, TRAPMASK, TRAP | Events (read, write-1-to-clear); trap mask; vector, cause, saved PC |
| 0x14–0x16 | PINCFG0/1, SHIFTCFG | Pin bases, jmp pin, output-enable mode, wired-AND with the other SM; shift direction, autopull and autopush thresholds |
| 0x17–0x19 | TOUT, JMPSEL, IRQEN | Timeout in ticks; event select for `jmp`; CPU interrupt enables |
| 0x80+ | Global | CPU control, IRQ status, two 16-bit timers, host mailbox, direct pin access, SM program write port |

## 4. Protocol CPU

16 bit, 8 registers (r7 is the link register), program and data in the shared
1024×16 SRAM. Two cycles per instruction (fetch, execute); three for a load or
store. No pipeline, so branches cost the same either way.

| [15:12] | Form | Meaning |
| --- | --- | --- |
| 0x0 | `alu rd, rs, fn` | add, sub, adc, sbc, and, or, xor, mov, cmp, tst, lsl, lsr, asr, swap bytes, neg, not |
| 0x1 | `ldi rd, imm8` / `ldih rd, imm8` | Load low or high byte |
| 0x2 | `addi rd, simm8` | |
| 0x3 | `cmpi rd, imm8` | |
| 0x4 | `andi` / `xori rd, imm8` | |
| 0x5 | `ld rd, [rs+off6]` | |
| 0x6 | `st rd, [rs+off6]` | |
| 0x7 | `ldp rd, [rs]+` / `stp rd, [rs]+` | Post-increment, for copy loops between SRAM and FIFOs |
| 0x8 | `in rd, io8` | Read I/O register |
| 0x9 | `out io8, rs` | Write I/O register |
| 0xA | `b<cc> rel8` | 16 conditions |
| 0xB | `jal rel12` | |
| 0xC | `jr rs` / `reti` | |
| 0xD | `sbis` / `sbic io5, bit` | Skip next instruction if an I/O bit is set or clear |
| 0xE | `wfe mask` | Sleep until a selected event; wake latency is one cycle |
| 0xF | reserved | L1 experiment only: `crcstep`, run-detect, bit-reverse. L0 and L2 leave this empty, so E1 compares the same CPU. |

Interrupts: one vector, no nesting. Deadline-critical code uses `wfe` so the
latency is fixed.

## 5. Host port, reset and pins

- **Reset.** rst_n halts the CPU, disables both SMs, releases every protocol pin
  and leaves the host port live. Nothing runs until the host sets the run bit.
- **Host port.** SPI target, mode 0, in fixed logic so it works with no firmware
  loaded. Commands: write memory, read memory, write I/O, read I/O, control (CPU
  run, SM enables, soft reset). Addresses auto-increment. See section 7 for what
  milestone 1 implements.
- **Load sequence.** The host writes the SRAM image, both SM programs and all
  configuration registers, then sets run.
- **Memory arbitration.** The shared SRAM is single-port. A host access while the
  CPU runs stalls the CPU for one cycle. State machines never stall; their
  program memories are private.

| Pins | Use |
| --- | --- |
| ui[0..2] | Host SCK, COPI, CS_n (order fixed in M1, see 7.1) |
| uo[0..1] | Host CIPO, IRQ |
| ui[3..7] | 5 protocol inputs |
| uo[2..7] | 6 protocol outputs |
| uio[0..7] | 8 bidirectional protocol pins (USB D+ and D−, I2C SDA and SCL, SWDIO, 1-Wire) |

## 6. Open questions carried from the sketch

1. **SM fetch timing.** Partly answered in 7.3: the 256×16 macro leaves about
   11 ns of a 16.7 ns cycle after its output is valid.
2. **Manchester receive.** Is LIMIT/IGNORE resync at 6 samples per bit enough for
   10BASE-T receive, or does it need its own mode?
3. **One-SM CAN.** A transmitter that loses arbitration holds the same CRC and
   stuff state a receiver would. A direction swap that preserves state would let
   one SM do CAN. E2 experiment.
4. **Field length.** `tx` and `rx` encode up to 32 bits but OSR and ISR are 16.
   Either cap at 16 or let autopull and autopush span a field.
5. **Event latency.** One registered cycle is assumed. Confirm it closes timing
   with the trap path.
6. **Inter-packet minimum delay** (from the program sketches): either the SM waits
   on a tick count before the handshake, or the CPU times its EXEC.
7. **Profile table size** (from the sketches): CAN uses all four profiles; a
   "re-initialise LFSR on entry" profile bit would save one instruction per frame.

## 7. Milestone 1 review

### 7.1 Decided by the skeleton RTL

- **Host pin order** is SCK = ui[0], COPI = ui[1], CS_n = ui[2], CIPO = uo[0],
  IRQ = uo[1]. The sketch listed ui[0..2] as SCK, CS_n, MOSI; the RTL order is now
  the reference.
- **One address space.** M1 maps memories and CSRs into one 16-bit word address
  space (shared SRAM at 0x0000, SM SRAMs at 0x1000/0x1100, CSRs at 0x8000), so the
  host needs only READ (0x03) and WRITE (0x02). Separate I/O commands are not
  needed; the 0x80+ global I/O block of section 3 can live at 0x8000+ for the
  host and at io8 0x80+ for the CPU.
- **Read latency.** READ has one dummy byte after the address, not a status
  byte. A status byte is still possible later as a separate opcode.
- **SM program loading.** The host writes SM programs directly into the SM SRAMs
  (0x1000, 0x1100) instead of through a program write port. Keep the port only
  if the CPU must rewrite SM programs at run time.

### 7.2 Settled by the PDK

- `ihp-sg13cmos5l/libs.ref/sg13cmos5l_sram` is a symlink to
  `ihp-sg13g2/libs.ref/sg13g2_sram`. The CMOS5L macros are the SG13G2 macros, so
  the sizes in [design-sketch.md](design-sketch.md) hold: 1024×16 is 236.80 × 336.46 µm and 256×16 is
  236.80 × 118.78 µm.
- The PDK now also has `RM_IHPSG13_1P_64x16_c2` (236.80 × 64.36 µm, no BIST).
  It matters only for the fallback: a 64×16
  macro is 15,240 µm², about half a 256×16, and is an alternative to the latch
  store if 256 instructions per SM turn out to be far more than needed.
- **Power on CMOS5L.** The tile's PDN is vertical Metal4 stripes only, and the
  macros' power pins are vertical Metal4 columns at an 11.24 µm pitch. The flow
  powers them by matching the stripe pitch to the columns (44.96 µm) and
  extending the stripes over the macros after PDN generation (see
  [architecture.md](architecture.md#floorplan-and-power)). Consequence for the
  floorplan: macros sit at x = 3.36 + n × 11.24 µm, and stacked macros must share
  x.

### 7.3 Timing numbers for the SM fetch question

Clock-to-output of the macros, from the PDK Liberty files (A_CLK → A_DOUT, rise,
smallest load):

| Macro | Typical (1.20 V, 25 °C) | Slow (1.08 V, 125 °C) |
| --- | --- | --- |
| 256×16 (SM program) | — | 5.0 ns |
| 1024×16 (shared) | 4.3 ns | 7.1 ns |

At 60 MHz (16.67 ns), an SM fetch from its 256×16 macro leaves about 11 ns in the
slow corner for condition decode and next-PC setup. A single-cycle taken `jmp`
looks feasible; the first hardened SM in milestone 2 gives the real number.
The CPU's fetch from the 1024×16 macro leaves about 9 ns, which is consistent with
the two-cycle instruction in section 4.
