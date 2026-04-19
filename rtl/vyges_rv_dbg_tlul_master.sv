// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Vyges
//
// vyges_rv_dbg_tlul_master — plain req/gnt master ↔ TL-UL master adapter.
// Converts pulp dm_sba master_* signals into outgoing TL-UL A-channel
// transactions; returns D-channel response back via master_r_* signals.
// Single-outstanding.

module vyges_rv_dbg_tlul_master
  import tlul_pkg::*;
#(
    parameter int unsigned       BusWidth = 32,
    parameter logic [top_pkg::TL_AIW-1:0] SourceId = 'h0
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

    `ifndef SYNTHESIS
    initial begin
        if (BusWidth != top_pkg::TL_DW) begin
            $error("vyges_rv_dbg_tlul_master: BusWidth (%0d) must match TL_DW (%0d)",
                   BusWidth, top_pkg::TL_DW);
        end
    end
    `endif

    typedef enum logic [1:0] {
        M_IDLE   = 2'b00,
        M_AISSUE = 2'b01,
        M_DWAIT  = 2'b10
    } state_e;

    state_e state_q, state_d;

    // Latched master-side request
    logic                         we_q;
    logic [BusWidth-1:0]          addr_q;
    logic [BusWidth/8-1:0]        be_q;
    logic [BusWidth-1:0]          wdata_q;

    // ── FSM transitions ──────────────────────────────────────────────
    always_comb begin
        state_d = state_q;
        unique case (state_q)
            M_IDLE:   if (master_req_i)   state_d = M_AISSUE;
            M_AISSUE: begin
                if (tl_h_i.a_ready && tl_h_i.d_valid) state_d = M_IDLE;
                else if (tl_h_i.a_ready)              state_d = M_DWAIT;
            end
            M_DWAIT:  if (tl_h_i.d_valid) state_d = M_IDLE;
            default:                      state_d = M_IDLE;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= M_IDLE;
            we_q    <= 1'b0;
            addr_q  <= '0;
            be_q    <= '0;
            wdata_q <= '0;
        end else begin
            state_q <= state_d;

            // Latch master request on IDLE → AISSUE
            if (state_q == M_IDLE && master_req_i) begin
                we_q    <= master_we_i;
                addr_q  <= master_add_i;
                be_q    <= master_be_i;
                wdata_q <= master_wdata_i;
            end
        end
    end

    // ── Grant handshake to pulp master ───────────────────────────────
    // gnt pulses for one cycle when we accept the request into the FSM.
    // Matches the "accept on gnt" convention used by pulp dm_sba.
    assign master_gnt_o = (state_q == M_IDLE) && master_req_i;

    // ── TL-UL A-channel output ───────────────────────────────────────
    // Build the pre-integrity packet; tlul_cmd_intg_gen below fills in
    // the correct a_user.cmd_intg + data_intg so slaves that check command
    // integrity (uart_reg_top, tlul_sram_byte, etc.) accept the request
    // instead of returning d_error=1 with DataWhenError (0xffffffff).
    tl_h2d_t tl_h_o_pre;
    always_comb begin
        tl_h_o_pre           = TL_H2D_DEFAULT;
        tl_h_o_pre.a_valid   = (state_q == M_AISSUE);
        tl_h_o_pre.a_opcode  = we_q ? ((&be_q) ? PutFullData : PutPartialData)
                                    : Get;
        tl_h_o_pre.a_size    = top_pkg::TL_SZW'($clog2(BusWidth/8));
        tl_h_o_pre.a_source  = SourceId;
        tl_h_o_pre.a_address = {{(top_pkg::TL_AW-BusWidth){1'b0}}, addr_q};
        tl_h_o_pre.a_mask    = be_q;
        tl_h_o_pre.a_data    = {{(top_pkg::TL_DW-BusWidth){1'b0}}, wdata_q};
        tl_h_o_pre.a_user    = TL_A_USER_DEFAULT;
        tl_h_o_pre.d_ready   = 1'b1;
    end

    tlul_cmd_intg_gen #(
        .EnableDataIntgGen(1)
    ) u_cmd_intg_gen (
        .tl_i (tl_h_o_pre),
        .tl_o (tl_h_o)
    );

    // ── Response back to pulp master ─────────────────────────────────
    assign master_r_valid_o     = ((state_q == M_AISSUE && tl_h_i.a_ready) ||
                                    (state_q == M_DWAIT)) && tl_h_i.d_valid;
    assign master_r_rdata_o     = tl_h_i.d_data[BusWidth-1:0];
    assign master_r_err_o       = tl_h_i.d_error;
    assign master_r_other_err_o = 1'b0;  // reserved — TL-UL surfaces only d_error

endmodule
