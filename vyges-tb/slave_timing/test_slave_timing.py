# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Vyges
#
# test_slave_timing — drives a sequence of TL-UL Get transactions through
# vyges_rv_dbg_tlul_slave and asserts that each response carries the
# CURRENT transaction's data, not the previous one. If d_data ever
# matches GOLDEN(prev_addr) instead of GOLDEN(curr_addr), the slave
# adapter has reverted to the off-by-one sample-during-PENDING bug.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly


def golden(addr: int) -> int:
    """Match the pulp-slave-mimic in tb_slave_timing.sv. Must depend on
    every bit of addr so distinct addrs always yield distinct rdata —
    otherwise an off-by-one might alias to the correct value by accident.
    """
    return (addr ^ 0xCAFE_BABE) & 0xFFFF_FFFF


# TL-UL A-channel opcodes
PUT_FULL_DATA = 0
PUT_PARTIAL   = 1
GET           = 4


async def reset(dut):
    dut.rst_ni.value       = 0
    dut.drv_a_valid.value  = 0
    dut.drv_a_opcode.value = 0
    dut.drv_a_address.value = 0
    dut.drv_a_data.value   = 0
    dut.drv_a_mask.value   = 0
    dut.drv_d_ready.value  = 1
    for _ in range(4):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk_i)


async def tl_get(dut, addr: int) -> int:
    """Issue exactly ONE TL-UL Get and return its response data.

    Holding a_valid high for multiple cycles risks issuing a second
    transaction once the slave returns to IDLE — and with the off-by-one
    bug, the second transaction returns the first transaction's data,
    which silently masks the bug. So drive a_valid for exactly one edge.
    """
    dut.drv_a_valid.value   = 1
    dut.drv_a_opcode.value  = GET
    dut.drv_a_address.value = addr
    dut.drv_a_mask.value    = 0xF
    dut.drv_a_data.value    = 0

    # Caller arrives with state==IDLE (a_ready=1). One rising edge
    # accepts the transaction. Deassert a_valid immediately afterwards so
    # the slave can't accept a second one when it returns to IDLE.
    await RisingEdge(dut.clk_i)
    dut.drv_a_valid.value = 0

    # Wait for the response on the d-channel.
    while True:
        await RisingEdge(dut.clk_i)
        if int(dut.obs_d_valid.value) == 1:
            break

    rdata = int(dut.obs_d_data.value)
    err   = int(dut.obs_d_error.value)
    assert err == 0, f"d_error=1 on Get to 0x{addr:08x}"
    # One more edge to consume the response cycle (drv_d_ready=1 → state
    # transitions back to IDLE).
    await RisingEdge(dut.clk_i)
    return rdata


@cocotb.test()
async def slave_d_data_matches_current_request(dut):
    """For a sequence of distinct addresses, each TL-UL response must
    return GOLDEN(addr) — not GOLDEN(previous_addr). A failure here
    indicates the slave adapter is sampling slave_rdata_i one cycle too
    early (during S_PENDING instead of S_RESPOND).
    """
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    await reset(dut)

    # Warm-up read — pulp-slave-mimic's rdata_q starts at 0; first
    # response after reset is uncertain. Discard.
    await tl_get(dut, 0x0000_0800)

    # Span addresses that exercise the DM's typical fetch pattern:
    # debug ROM, WhereTo, AbstractCmd, ProgBuf, and the 0x000 region.
    addrs = [
        0x0001_0800,
        0x0001_0808,
        0x0001_0300,
        0x0001_0338,
        0x0001_0360,
        0x0000_0000,
        0x0000_0004,
    ]

    for a in addrs:
        rdata = await tl_get(dut, a)
        expected = golden(a)
        assert rdata == expected, (
            f"addr=0x{a:08x}: got 0x{rdata:08x}, expected 0x{expected:08x} "
            f"— off-by-one bug appears to have returned. The slave adapter "
            f"is likely sampling slave_rdata_i during S_PENDING instead of "
            f"reading it combinationally during S_RESPOND."
        )

    cocotb.log.info(
        "PASS — %d transactions, no off-by-one detected", len(addrs)
    )


@cocotb.test()
async def slave_d_data_changes_across_back_to_back_reads(dut):
    """A targeted check: two back-to-back reads to DIFFERENT addresses
    must produce DIFFERENT d_data. If they match, the second response
    is carrying the first request's data (off-by-one)."""
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    await reset(dut)

    # Warm-up so the pulp-slave-mimic's rdata_q has a defined value.
    await tl_get(dut, 0x0000_0800)

    r1 = await tl_get(dut, 0x0000_0AAA)
    r2 = await tl_get(dut, 0x0000_0BBB)

    assert r1 != r2, (
        f"back-to-back reads returned identical d_data (0x{r1:08x}); "
        f"strong indicator of off-by-one — the second request returned "
        f"the first request's data."
    )
    assert r1 == golden(0x0000_0AAA), f"r1 = 0x{r1:08x}"
    assert r2 == golden(0x0000_0BBB), f"r2 = 0x{r2:08x}"
