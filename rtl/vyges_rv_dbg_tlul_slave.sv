// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Vyges
//
// vyges_rv_dbg_tlul_slave — TL-UL slave ↔ plain req/gnt slave adapter.
// Serializes A-channel transactions onto pulp dm_top.slave_* (single-cycle
// latency) and returns rdata on the D-channel.

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

    // verilog_lint: waive-start line-length
    // Only BusWidth == TL_DW supported in this adapter. Assert at elab.
    `ifndef SYNTHESIS
    initial begin
        if (BusWidth != top_pkg::TL_DW) begin
            $error("vyges_rv_dbg_tlul_slave: BusWidth (%0d) must match TL_DW (%0d)",
                   BusWidth, top_pkg::TL_DW);
        end
    end
    `endif

    typedef enum logic [1:0] {
        S_IDLE    = 2'b00,
        S_PENDING = 2'b01,
        S_RESPOND = 2'b10
    } state_e;

    (* mark_debug = "true", keep = "true" *) state_e state_q;
    state_e state_d;

    // Latched A-channel fields
    logic                         we_q;
    (* mark_debug = "true", keep = "true" *) logic [BusWidth-1:0]          addr_q;
    logic [BusWidth/8-1:0]        be_q;
    logic [BusWidth-1:0]          wdata_q;
    logic [top_pkg::TL_AIW-1:0]   source_q;
    logic [top_pkg::TL_SZW-1:0]   size_q;

    // Captured read data from pulp (registered at end of PENDING)
    (* mark_debug = "true", keep = "true" *) logic [BusWidth-1:0]          rdata_q;

    // ── FSM transitions ──────────────────────────────────────────────
    always_comb begin
        state_d = state_q;
        unique case (state_q)
            S_IDLE:    if (tl_d_i.a_valid)     state_d = S_PENDING;
            S_PENDING:                          state_d = S_RESPOND;
            S_RESPOND: if (tl_d_i.d_ready)     state_d = S_IDLE;
            default:                            state_d = S_IDLE;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q  <= S_IDLE;
            we_q     <= 1'b0;
            addr_q   <= '0;
            be_q     <= '0;
            wdata_q  <= '0;
            source_q <= '0;
            size_q   <= '0;
            rdata_q  <= '0;
        end else begin
            state_q <= state_d;

            // Latch A-channel on IDLE → PENDING
            if (state_q == S_IDLE && tl_d_i.a_valid) begin
                we_q     <= (tl_d_i.a_opcode == PutFullData) ||
                            (tl_d_i.a_opcode == PutPartialData);
                addr_q   <= tl_d_i.a_address[BusWidth-1:0];
                be_q     <= tl_d_i.a_mask;
                wdata_q  <= tl_d_i.a_data[BusWidth-1:0];
                source_q <= tl_d_i.a_source;
                size_q   <= tl_d_i.a_size;
            end

            // ILA-only observation flop. Latches slave_rdata_i during the
            // PENDING (req=1) cycle — i.e., pulp's PRE-edge rdata, which is
            // STALE (the previous transaction's data). Kept here only as a
            // diagnostic anchor for the off-by-one history captured 2026-04-26.
            // The d_data path (below) does NOT use this register.
            if (state_q == S_PENDING) begin
                rdata_q <= slave_rdata_i;
            end
        end
    end

    // ── Pulp slave-port outputs ──────────────────────────────────────
    assign slave_req_o   = (state_q == S_PENDING);
    assign slave_we_o    = we_q;
    assign slave_addr_o  = addr_q;
    assign slave_be_o    = be_q;
    assign slave_wdata_o = wdata_q;

    // ── TL-UL D-channel response ─────────────────────────────────────
    // Pre-integrity response; tlul_rsp_intg_gen below signs rsp_intg +
    // data_intg so CPU-side tlul_rsp_intg_chk accepts this slave's d-channel
    // on a signed TL-UL domain. See Bus security domain contract work item
    // in deckrun-server/docs/todo.md.
    //
    // d_data: combinational pass-through from slave_rdata_i during S_RESPOND.
    // pulp dm_top.slave_rdata_o is REGISTERED (rdata_q in dm_mem.sv); the
    // value for the request issued during S_PENDING (cycle N+1) becomes valid
    // at the edge into S_RESPOND (cycle N+2). slave_req_o is low in RESPOND,
    // so pulp's rdata_q stays stable for the whole RESPOND cycle. This matches
    // OpenTitan's pattern (`tlul_adapter_reg #(.AccessLatency(1))` driving
    // dm_top.slave_*) — see lowRISC opentitan @ 8007f61 hw/ip/rv_dm/rtl/rv_dm.sv.
    // An earlier hand-rolled version sampled slave_rdata_i during PENDING
    // (off-by-one) which returned the previous transaction's data. The §4.6
    // dm_mem warmup in rv_core_ibex_tlul.sv masked it for the FIRST halt-path
    // fetch (warmup primed pulp's rdata for HaltAddress = first real fetch
    // address — coincidental hit), but the abstract-cmd dispatch (fetches
    // into 0x300/0x338/0x360, never primed) hit cmderr=3.
    tl_d2h_t tl_d_o_pre;
    always_comb begin
        tl_d_o_pre          = TL_D2H_DEFAULT;
        tl_d_o_pre.a_ready  = (state_q == S_IDLE);
        tl_d_o_pre.d_valid  = (state_q == S_RESPOND);
        tl_d_o_pre.d_opcode = we_q ? AccessAck : AccessAckData;
        tl_d_o_pre.d_size   = size_q;
        tl_d_o_pre.d_source = source_q;
        tl_d_o_pre.d_data   = {{(top_pkg::TL_DW-BusWidth){1'b0}}, slave_rdata_i};
        tl_d_o_pre.d_error  = 1'b0;
    end

    tlul_rsp_intg_gen #(
        .EnableRspIntgGen  (1),
        .EnableDataIntgGen (1)
    ) u_rsp_intg_gen (
        .tl_i (tl_d_o_pre),
        .tl_o (tl_d_o)
    );

endmodule
