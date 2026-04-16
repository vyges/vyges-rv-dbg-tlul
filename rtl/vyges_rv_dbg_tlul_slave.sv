// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Vyges
//
// vyges_rv_dbg_tlul_slave — TL-UL slave ↔ plain req/gnt slave adapter.

module vyges_rv_dbg_tlul_slave
  import tlul_pkg::*;
#(
    parameter int unsigned BusWidth = 32
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,
    // TL-UL slave port
    input  tl_h2d_t               tl_d_i,
    output tl_d2h_t               tl_d_o,
    // dm_top slave side
    output logic                  slave_req_o,
    output logic                  slave_we_o,
    output logic [BusWidth-1:0]   slave_addr_o,
    output logic [BusWidth/8-1:0] slave_be_o,
    output logic [BusWidth-1:0]   slave_wdata_o,
    input  logic [BusWidth-1:0]   slave_rdata_i
);

    // TODO: adapter implementation
    assign tl_d_o        = '0;
    assign slave_req_o   = 1'b0;
    assign slave_we_o    = 1'b0;
    assign slave_addr_o  = '0;
    assign slave_be_o    = '0;
    assign slave_wdata_o = '0;

endmodule
