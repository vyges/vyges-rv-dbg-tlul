# slave_timing — vyges_rv_dbg_tlul_slave d_data sample timing regression

Verifies that `vyges_rv_dbg_tlul_slave` returns the **current** request's
`slave_rdata_i` on the TL-UL D-channel, not the previous request's data.

The slave adapter drives a connected DM port whose `slave_rdata_o` is
**registered** — valid one cycle after the request is issued. Sampling
`slave_rdata_i` during `S_PENDING` (the request cycle) would capture the
prior transaction's data; the adapter must read it combinationally during
`S_RESPOND` instead.

This test catches that mistake by:

1. Driving a sequence of distinct TL-UL Get requests through the adapter.
2. Mimicking the connected port with a 1-cycle-registered rdata generator.
3. Asserting each response's `d_data` matches the current request's
   address-derived golden value.

## Run

```sh
make            # uses Verilator + cocotb
make clean      # wipe sim_build/
```

By default the Makefile expects this directory to live two levels under
the repo root (i.e. `vyges-tb/slave_timing/`). Override `DBG_TLUL` if
you've vendored this test into a different layout.

## Prerequisites

- `verilator` (≥ 5.0) on PATH
- `cocotb` (≥ 1.9) reachable via `cocotb-config`
