# SPDX-FileCopyrightText: © 2026 Zixin (Stan) Wan
# SPDX-License-Identifier: Apache-2.0
#
# Milestone 1 tests: the host SPI port, the bus, the CSRs and all three SRAM
# macros. The same tests run on the RTL and on the gate-level netlist.

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, ReadOnly

CLK_PERIOD_PS = 16666  # 60 MHz
SCK_HALF = 4           # clk cycles per SCK half-period: SCK = clk / 8 = 7.5 MHz

OP_WRITE = 0x02
OP_READ = 0x03

CSR_ID, CSR_VERSION, CSR_SCRATCH, CSR_GPIO_OUT = 0x8000, 0x8001, 0x8002, 0x8003
CSR_GPIO_OE, CSR_GPIO_IN, CSR_IRQ, CSR_CYCLES = 0x8004, 0x8005, 0x8006, 0x8007

SHARED_BASE, SHARED_WORDS = 0x0000, 1024
SM0_BASE, SM1_BASE, SM_WORDS = 0x1000, 0x1100, 256

# ui_in bit positions
SCK, COPI, CSN = 0, 1, 2


class Host:
    """Bit-banged SPI controller (mode 0) on ui_in[2:0], CIPO on uo_out[0]."""

    def __init__(self, dut):
        self.dut = dut
        self.ui = 1 << CSN  # CS_n idle high, SCK idle low

    def _set(self, bit, val):
        if val:
            self.ui |= 1 << bit
        else:
            self.ui &= ~(1 << bit)
        self.dut.ui_in.value = self.ui

    async def _xfer_bit(self, out_bit):
        # Mode 0: data set up while SCK is low, sampled on the rising edge.
        self._set(COPI, out_bit)
        await ClockCycles(self.dut.clk, SCK_HALF)
        self._set(SCK, 1)
        await ReadOnly()
        in_bit = int(self.dut.uo_out.value) & 1
        await ClockCycles(self.dut.clk, SCK_HALF)
        self._set(SCK, 0)
        return in_bit

    async def _xfer(self, value, nbits):
        result = 0
        for i in reversed(range(nbits)):
            result = (result << 1) | await self._xfer_bit((value >> i) & 1)
        return result

    async def _begin(self):
        self._set(CSN, 0)
        await ClockCycles(self.dut.clk, SCK_HALF)

    async def _end(self):
        await ClockCycles(self.dut.clk, SCK_HALF)
        self._set(CSN, 1)
        await ClockCycles(self.dut.clk, 2 * SCK_HALF)

    async def write(self, addr, words):
        await self._begin()
        await self._xfer(OP_WRITE, 8)
        await self._xfer(addr, 16)
        for w in words:
            await self._xfer(w, 16)
        await self._end()

    async def read(self, addr, n=1):
        await self._begin()
        await self._xfer(OP_READ, 8)
        await self._xfer(addr, 16)
        await self._xfer(0, 8)  # dummy byte
        words = [await self._xfer(0, 16) for _ in range(n)]
        await self._end()
        return words

    async def write1(self, addr, word):
        await self.write(addr, [word])

    async def read1(self, addr):
        return (await self.read(addr, 1))[0]


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, unit="ps").start())
    dut.ena.value = 1
    dut.ui_in.value = 1 << CSN
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)
    return Host(dut)


@cocotb.test()
async def test_id_and_scratch(dut):
    host = await setup(dut)
    assert await host.read1(CSR_ID) == 0xB175
    assert await host.read1(CSR_VERSION) == 0x0001
    for v in (0x0000, 0xFFFF, 0xA55A, 0x1234):
        await host.write1(CSR_SCRATCH, v)
        assert await host.read1(CSR_SCRATCH) == v
    # Unmapped addresses read 0; an unknown opcode is ignored.
    assert await host.read1(0x4000) == 0
    await host._begin()
    await host._xfer(0x9F, 8)
    await host._xfer(0xFFFF, 16)
    await host._end()
    assert await host.read1(CSR_SCRATCH) == 0x1234


@cocotb.test()
async def test_cycle_counter(dut):
    host = await setup(dut)
    a = await host.read1(CSR_CYCLES)
    b = await host.read1(CSR_CYCLES)
    # Back-to-back single-word reads are a fixed number of clk cycles apart.
    delta = (b - a) & 0xFFFF
    expected = (8 + 16 + 8 + 16) * 2 * SCK_HALF + 4 * SCK_HALF  # bits + begin/end gaps
    assert abs(delta - expected) <= 4, f"cycle delta {delta}, expected about {expected}"


@cocotb.test()
async def test_shared_sram(dut):
    host = await setup(dut)
    rng = random.Random(1)
    # Burst at both ends of the address range and in the middle.
    for base in (SHARED_BASE, SHARED_BASE + 500, SHARED_BASE + SHARED_WORDS - 8):
        data = [rng.randrange(1 << 16) for _ in range(8)]
        await host.write(base, data)
        assert await host.read(base, 8) == data, f"burst at 0x{base:04x}"
    # Single words, written out of order.
    addrs = rng.sample(range(SHARED_WORDS), 16)
    golden = {a: rng.randrange(1 << 16) for a in addrs}
    for a, v in golden.items():
        await host.write1(SHARED_BASE + a, v)
    for a in sorted(golden):
        assert await host.read1(SHARED_BASE + a) == golden[a], f"word 0x{a:03x}"


@cocotb.test()
async def test_sm_srams(dut):
    host = await setup(dut)
    rng = random.Random(2)
    for base in (SM0_BASE, SM1_BASE):
        for off in (0, 120, SM_WORDS - 4):
            data = [rng.randrange(1 << 16) for _ in range(4)]
            await host.write(base + off, data)
            assert await host.read(base + off, 4) == data, f"burst at 0x{base + off:04x}"


@cocotb.test()
async def test_memories_are_separate(dut):
    host = await setup(dut)
    tags = {SHARED_BASE: 0x5A00, SM0_BASE: 0x5A01, SM1_BASE: 0x5A02}
    for base, tag in tags.items():
        await host.write1(base + 7, tag)
    for base, tag in tags.items():
        assert await host.read1(base + 7) == tag
    # The 256-word SRAMs decode only their own 256 words.
    await host.write1(SM0_BASE + 0xFF, 0x00FF)
    await host.write1(SM1_BASE + 0x00, 0x0100)
    assert await host.read1(SM0_BASE + 0xFF) == 0x00FF
    assert await host.read1(SM1_BASE + 0x00) == 0x0100


@cocotb.test()
async def test_gpio_and_irq(dut):
    host = await setup(dut)
    await host.write1(CSR_GPIO_OUT, 0xA52A)
    await host.write1(CSR_GPIO_OE, 0x00F0)
    await ClockCycles(dut.clk, 2)
    assert (int(dut.uo_out.value) >> 2) == 0x2A
    assert int(dut.uio_out.value) == 0xA5
    assert int(dut.uio_oe.value) == 0xF0
    assert await host.read1(CSR_GPIO_OUT) == 0xA52A

    dut.uio_in.value = 0x3C
    host._set(7, 1)
    host._set(4, 1)
    await ClockCycles(dut.clk, 4)
    v = await host.read1(CSR_GPIO_IN)
    assert v >> 8 == 0x3C
    assert (v & 0xF8) == 0x90  # ui_in[7:3]; [2:0] are the host pins

    assert (int(dut.uo_out.value) >> 1) & 1 == 0
    await host.write1(CSR_IRQ, 1)
    await ClockCycles(dut.clk, 2)
    assert (int(dut.uo_out.value) >> 1) & 1 == 1
    await host.write1(CSR_IRQ, 0)
    await ClockCycles(dut.clk, 2)
    assert (int(dut.uo_out.value) >> 1) & 1 == 0


@cocotb.test()
async def test_cipo_idle_low(dut):
    host = await setup(dut)
    await host.write1(SHARED_BASE, 0xFFFF)
    await host.read1(SHARED_BASE)
    await ClockCycles(dut.clk, 4)
    assert int(dut.uo_out.value) & 1 == 0
