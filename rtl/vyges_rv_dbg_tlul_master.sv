// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Vyges
//
// vyges_rv_dbg_tlul_master — plain req/gnt master ↔ TL-UL master adapter.

module vyges_rv_dbg_tlul_master
  import tlul_pkg::*;
#(
    parameter int unsigned BusWidth      = 32,
    parameter logic [TL_AIW-1:0] SourceId = 'h0
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,
    // dm_top master side
    input  logic                  master_req_i,
    input  logic [BusWidth-1:0]   master_add_i,
    input  logic                  master_we_i,
    input  logic [BusWidth-1:0]   master_wdata_i,
    input  logic [BusWidth/8-1:0] master_be_i,
    output logic                  master_gnt_o,
    output logic                  master_r_valid_o,
    output logic                  master_r_err_o,
    output logic                  master_r_other_err_o,
    output logic [BusWidth-1:0]   master_r_rdata_o,
    // TL-UL host port
    output tl_h2d_t               tl_h_o,
    input  tl_d2h_t               tl_h_i
);

    // TODO: adapter implementation
    assign tl_h_o               = '0;
    assign master_gnt_o         = 1'b0;
    assign master_r_valid_o     = 1'b0;
    assign master_r_err_o       = 1'b0;
    assign master_r_other_err_o = 1'b0;
    assign master_r_rdata_o     = '0;

endmodule
