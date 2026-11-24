<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

Inline Bitstream Transforms is a programmable protocol emulator for the Jane Street Protocol Emulator ASIC
competition. The final design has a small protocol CPU and two field-level state machines; each state machine
has a bit timer and an inline transform unit (CRC LFSR, bit stuffing, NRZI/Manchester coding) so that per-bit
work costs no instructions.

This version is the milestone 1 skeleton. It contains the host SPI port, a 16-bit word bus, a few control
registers and the three IHP SRAM macros of the final design: a shared 1024x16 SRAM and one 256x16 program SRAM
per state machine. The protocol pins are driven from control registers.

The host talks SPI mode 0 (SCK at most clk / 8). A frame is an opcode byte, a 16-bit word address and then
16-bit data words with auto-increment:

- write: `0x02 addr_hi addr_lo d0_hi d0_lo d1_hi d1_lo ...`
- read: `0x03 addr_hi addr_lo dummy`, then the data words come out on CIPO

| Word address | Target |
| --- | --- |
| 0x0000-0x03FF | shared SRAM (1024x16) |
| 0x1000-0x10FF | state machine 0 SRAM (256x16) |
| 0x1100-0x11FF | state machine 1 SRAM (256x16) |
| 0x8000 | ID, reads 0xB175 |
| 0x8001 | version, reads 0x0001 |
| 0x8002 | scratch register |
| 0x8003 | GPIO_OUT: bits 5:0 drive uo[7:2], bits 15:8 drive uio[7:0] |
| 0x8004 | GPIO_OE: bits 7:0 enable uio[7:0] as outputs |
| 0x8005 | GPIO_IN: {uio_in, ui_in} |
| 0x8006 | IRQ: bit 0 drives uo[1] |
| 0x8007 | free-running cycle counter |

## How to test

Run the clock at up to 60 MHz and reset the design. Connect an SPI controller (for example the RP2350 on the
demo board) to ui[0] (SCK), ui[1] (COPI), ui[2] (CS_n) and uo[0] (CIPO).

1. Read word 0x8000: it returns 0xB175.
2. Write a few words to 0x0000, 0x1000 and 0x1100, then read them back.
3. Write 0x00FF to GPIO_OE (0x8004) and a value to GPIO_OUT (0x8003), and check uo[7:2] and uio[7:0].

## External hardware

An SPI controller (microcontroller) for the host port.
