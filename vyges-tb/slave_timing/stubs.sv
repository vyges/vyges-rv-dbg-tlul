// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Vyges
//
// Test-only stubs — minimal top_pkg + tlul_pkg + a pass-through
// tlul_rsp_intg_gen so vyges_rv_dbg_tlul_slave can elaborate standalone.
// This deliberately does NOT pull in the full opentitan-tlul / opentitan-prim
// chain; this regression covers ONLY the slave-port d_data sample timing.

package top_pkg;
  parameter int TL_AW   = 32;
  parameter int TL_DW   = 32;
  parameter int TL_AIW  = 8;
  parameter int TL_DIW  = 1;
  parameter int TL_DBW  = TL_DW / 8;
  parameter int TL_SZW  = 2;
  parameter int TL_AUW  = 14;
endpackage

package tlul_pkg;

  typedef enum logic [2:0] {
    PutFullData    = 3'h 0,
    PutPartialData = 3'h 1,
    Get            = 3'h 4
  } tl_a_op_e;

  typedef enum logic [2:0] {
    AccessAck     = 3'h 0,
    AccessAckData = 3'h 1
  } tl_d_op_e;

  // Stripped user types (no integrity in this test).
  typedef logic [top_pkg::TL_AUW-1:0] tl_a_user_t;
  typedef logic [top_pkg::TL_AUW-1:0] tl_d_user_t;

  parameter tl_a_user_t TL_A_USER_DEFAULT = '0;
  parameter tl_d_user_t TL_D_USER_DEFAULT = '0;

  typedef struct packed {
    logic                          a_valid;
    tl_a_op_e                      a_opcode;
    logic                  [2:0]   a_param;
    logic  [top_pkg::TL_SZW-1:0]   a_size;
    logic  [top_pkg::TL_AIW-1:0]   a_source;
    logic   [top_pkg::TL_AW-1:0]   a_address;
    logic  [top_pkg::TL_DBW-1:0]   a_mask;
    logic   [top_pkg::TL_DW-1:0]   a_data;
    tl_a_user_t                    a_user;
    logic                          d_ready;
  } tl_h2d_t;

  parameter tl_h2d_t TL_H2D_DEFAULT = '{
    d_ready:  1'b1,
    a_opcode: tl_a_op_e'('0),
    a_user:   TL_A_USER_DEFAULT,
    default:  '0
  };

  typedef struct packed {
    logic                          d_valid;
    tl_d_op_e                      d_opcode;
    logic                   [2:0]  d_param;
    logic  [top_pkg::TL_SZW-1:0]   d_size;
    logic  [top_pkg::TL_AIW-1:0]   d_source;
    logic  [top_pkg::TL_DIW-1:0]   d_sink;
    logic   [top_pkg::TL_DW-1:0]   d_data;
    tl_d_user_t                    d_user;
    logic                          d_error;
    logic                          a_ready;
  } tl_d2h_t;

  parameter tl_d2h_t TL_D2H_DEFAULT = '{
    a_ready:  1'b1,
    d_opcode: tl_d_op_e'('0),
    d_user:   TL_D_USER_DEFAULT,
    default:  '0
  };

endpackage

// Pass-through stub for tlul_rsp_intg_gen. The production module signs
// rsp_intg + data_intg fields of tl_o.d_user; for the slave-port timing
// regression we don't care about integrity, so we forward the d2h
// structure unchanged.
module tlul_rsp_intg_gen
  import tlul_pkg::*;
#(
  parameter bit EnableRspIntgGen  = 1,
  parameter bit EnableDataIntgGen = 1,
  parameter bit UserInIsZero      = 0,
  parameter bit RspIntgInIsZero   = 0
) (
  input  tl_d2h_t tl_i,
  output tl_d2h_t tl_o
);
  assign tl_o = tl_i;
endmodule
