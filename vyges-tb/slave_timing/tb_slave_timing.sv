// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Vyges
//
// tb_slave_timing — regression for vyges_rv_dbg_tlul_slave's d_data sample
// timing relative to the connected slave port's registered rdata. The
// pulp-slave-mimic below behaves exactly like dm_top.slave_rdata_o (1-cycle
// latency from req): for each request issued in cycle N, the rdata is
// valid in cycle N+1. The DUT must return that valid rdata as d_data on
// the TL-UL D-channel; if it samples one cycle early, the response carries
// the previous transaction's data and the assertions in test_slave_timing.py
// will fail.

module tb_slave_timing
  import tlul_pkg::*;
();

    // ── Clock + reset (cocotb drives both via flat ports) ───────────
    logic clk_i  = 0;
    logic rst_ni = 0;

    // ── Cocotb-driven flat signals ───────────────────────────────────
    // Driving struct fields via cocotb is finicky across simulators;
    // expose the subset we need as flat scalars.
    logic        drv_a_valid;
    logic [2:0]  drv_a_opcode;
    logic [31:0] drv_a_address;
    logic [31:0] drv_a_data;
    logic [3:0]  drv_a_mask;
    logic        drv_d_ready;

    logic        obs_a_ready;
    logic        obs_d_valid;
    logic [31:0] obs_d_data;
    logic        obs_d_error;

    // Observation counter — if ever non-zero on a passing run, something
    // about the bench is unstable.
    int unsigned obs_d_valid_pulses = 0;
    always_ff @(posedge clk_i) begin
        if (obs_d_valid && drv_d_ready) obs_d_valid_pulses <= obs_d_valid_pulses + 1;
    end

    // ── Bridge flat ↔ struct ─────────────────────────────────────────
    tl_h2d_t tl_d_i;
    tl_d2h_t tl_d_o;

    always_comb begin
        tl_d_i           = TL_H2D_DEFAULT;
        tl_d_i.a_valid   = drv_a_valid;
        tl_d_i.a_opcode  = tl_a_op_e'(drv_a_opcode);
        tl_d_i.a_size    = top_pkg::TL_SZW'(2);  // 32-bit access
        tl_d_i.a_source  = top_pkg::TL_AIW'(0);
        tl_d_i.a_address = drv_a_address;
        tl_d_i.a_mask    = drv_a_mask;
        tl_d_i.a_data    = drv_a_data;
        tl_d_i.d_ready   = drv_d_ready;
    end

    assign obs_a_ready = tl_d_o.a_ready;
    assign obs_d_valid = tl_d_o.d_valid;
    assign obs_d_data  = tl_d_o.d_data[31:0];
    assign obs_d_error = tl_d_o.d_error;

    // ── DUT ──────────────────────────────────────────────────────────
    logic        slave_req;
    logic        slave_we;
    logic [31:0] slave_addr;
    logic [3:0]  slave_be;
    logic [31:0] slave_wdata;
    logic [31:0] slave_rdata;

    vyges_rv_dbg_tlul_slave #(
        .BusWidth(32)
    ) u_dut (
        .clk_i,
        .rst_ni,
        .tl_d_i,
        .tl_d_o,
        .slave_req_o   (slave_req),
        .slave_we_o    (slave_we),
        .slave_addr_o  (slave_addr),
        .slave_be_o    (slave_be),
        .slave_wdata_o (slave_wdata),
        .slave_rdata_i (slave_rdata)
    );

    // ── Pulp-slave-mimic (1-cycle registered rdata) ──────────────────
    // For each request in cycle N, return GOLDEN(addr) as rdata in cycle
    // N+1. This MUST be registered output: pulp dm_top.slave_rdata_o is
    // driven from dm_mem.rdata_q (registered). A combinational rdata
    // would mask the off-by-one bug we are guarding against.
    // Full 32-bit dependence on addr — masking to a subset of bits would
    // alias different addresses to the same rdata and miss the off-by-one.
    function automatic logic [31:0] golden(input logic [31:0] a);
        return a ^ 32'hCAFE_BABE;
    endfunction

    logic [31:0] rdata_q;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rdata_q <= '0;
        end else if (slave_req && !slave_we) begin
            rdata_q <= golden(slave_addr);
        end
    end
    assign slave_rdata = rdata_q;

    // ── Optional waveform dump (cocotb sets +trace via Makefile) ─────
    initial begin
        if ($test$plusargs("trace") != 0) begin
            $dumpfile("tb_slave_timing.vcd");
            $dumpvars(0, tb_slave_timing);
        end
    end

endmodule
