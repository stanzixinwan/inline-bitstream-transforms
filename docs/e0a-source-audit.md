# E0-a: source audit of three RP2040 protocol implementations

Proposal v5, experiment E0 (a): read Pico-PIO-USB, can2040 and one RP2040
10BASE-T TX project, and record what runs in PIO and what runs on the CPU, with
instruction and state-machine counts. This audit checks claims C1, C2 and C6 of
the proposal. Hardware measurement was optional and was not done.

Read on 2026-11-23:

| Project | Commit | Files read |
| --- | --- | --- |
| [sekigon-gonnoc/Pico-PIO-USB](https://github.com/sekigon-gonnoc/Pico-PIO-USB) | b186e36 (2026-10-23) | `src/usb_tx.pio`, `src/usb_rx.pio`, `src/pio_usb.c`, `src/pio_usb_device.c`, `src/usb_crc.c` |
| [KevinOConnor/can2040](https://github.com/KevinOConnor/can2040) | 2988d4f (2026-02-26) | `pio/can2040.pio`, `src/can2040.c` |
| [kingyoPiyo/Pico-10BASE-T](https://github.com/kingyoPiyo/Pico-10BASE-T) | a7f78cb (2024-08-16) | `src/ser_10base_t.pio`, `src/udp.c`, `src/main.c` |

## Summary

| | Pico-PIO-USB | can2040 | Pico-10BASE-T (TX) |
| --- | --- | --- | --- |
| State machines | 3 (TX in one PIO block; RX and edge/EOP detector in the other) | 4 of 4 in one PIO block | 1 |
| PIO instructions | 5 (TX) + 10 (NRZI decoder) + 17 (edge detector) = 32; the RX block uses 27 of 32 | 32 of 32 | 3 |
| PIO oversampling | 4× on TX, 8× on RX | 32× | 2× (one symbol per half-bit, 20 MHz) |
| Line coding | TX: NRZI on the CPU. RX: NRZI decode in PIO | NRZ (none needed) | Manchester on the CPU (256-entry table) |
| Bit stuffing | TX: on the CPU. RX: stuff bit dropped in PIO, **no stuff-error check** | TX and RX on the CPU | — |
| CRC | CRC5 and CRC16 on the CPU (tables); RX CRC16 checked per byte as bytes arrive | CRC15 on the CPU (table) | CRC-32 in the RP2040 DMA sniffer (a side-attached CRC unit); table on the CPU when DMA is off |
| How the in-frame deadline is met | Handshake chosen and data packet NRZI-encoded **before** the token arrives; CPU polls for EOP and fires a pre-encoded reply by DMA | CPU computes the expected **raw stuffed bits** of the CRC field while the frame arrives; the "match" SM compares them on the wire and injects ACK without the CPU | No deadline |
| Host bits per line bit | — | — | 4 (two 2-bit symbols per payload bit), precomputed in RAM |

## Findings against the proposal's claims

**C1 (Pico-PIO-USB and can2040 push NRZI, stuffing and destuffing to the CPU):
partly wrong; revise.** can2040 does push all of it to the CPU. Pico-PIO-USB at
this commit does NRZI decoding and drops stuff bits in PIO on receive
(`usb_nrzi_decoder`, 10 instructions), but does not check for stuff errors there.
NRZI encoding and stuffing on transmit, and both CRCs, stay on the CPU. The
claim should say "transmit coding, stuffing errors and CRC" for USB.

**C2 (USB uses 32 of 32 PIO instructions; CAN uses 4 of 4 SMs): holds, with a
correction.** can2040 uses all 32 instructions and all 4 SMs of one PIO block.
Pico-PIO-USB's three programs total 32 instructions but spread over two PIO
blocks (27 of 32 in the RX block). The NRZI decoder's comment still says
"15 instruction"; the assembled program is 10.

**C6 (RP2040 10BASE-T TX projects compute Manchester and CRC-32 on the CPU):
partly wrong; revise.** Manchester is on the CPU (a table lookup per byte). The
CRC-32 is computed by the RP2040's DMA sniffer while the frame is copied, which is
a side-attached hardware CRC unit, the L1 shape in E1. The CPU table is only the
fallback. This is a useful data point for E1: in practice a word-level side
accelerator already handles the 10BASE-T TX CRC, so class B is about host and
memory bandwidth, as Proposal v5 already argues.

## What this means for E1 and the design

1. **Deadlines are met by pre-computation, not by speed.** Both protocols with an
   in-frame deadline avoid computing anything after the last bit. Pico-PIO-USB
   decides the handshake before the token; can2040 turns the CRC check into a
   raw-bitstream compare that a state machine performs on the wire. The L0 and L1
   baselines in E1 must be allowed the same tricks, or the comparison is unfair.
   For CAN, can2040's trick needs the CPU to keep up with destuffing and CRC in
   real time during the frame; our CPU at about 30 MIPS has far less margin than
   an RP2040 at 120 MHz or more, which is exactly what E0-b should quantify.
2. **The CAN ACK trick is the strongest L0 argument.** It shows that a zero
   verdict latency is achievable without inline hardware, at the cost of one
   state machine and per-frame CPU work. E1 should count that SM: can2040 spends
   one of its four SMs on it.
3. **Pico-PIO-USB's receive path skips the stuff-error check.** A bit-stuffing
   violation is a protocol error the device should detect. The inline run-length
   stage gives that check for free; record it as a correctness point, not only a
   speed point.
4. **Pico-PIO-USB already does full-speed device on RP2040.** Its device mode
   meets the FS turnaround with pre-armed handshakes and per-byte CRC16 on a
   Cortex-M0+ clocked at a multiple of 12 MHz (typically 120 MHz or more). Proposal v5 calls FS USB the discriminating case; that
   stays true for a 30-MIPS protocol CPU, but the write-up must say the
   discriminating resource is CPU throughput during the frame, not the
   handshake deadline itself.
5. **10BASE-T TX host bandwidth.** The reference sends 4 bits of precomputed
   symbols per payload bit. With the inline coder and LFSR the host sends 1 bit
   per payload bit and no FCS (Design Sketch C.3).

## Not done

- No hardware measurement.
- The Pico-PIO-USB host path (`pio_usb_host.c`) was not read in detail.
- Instruction counts are from the assembled `.pio.h` (Pico-PIO-USB) and the
  program array in `can2040.c`; Pico-10BASE-T's count is from the `.pio` source.
