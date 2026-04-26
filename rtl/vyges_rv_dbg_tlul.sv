// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Vyges
//
// vyges_rv_dbg_tlul — TL-UL wrapper over pulp-platform/riscv-dbg dm_top.
// RISC-V Debug Spec 0.13. TL-UL slave (regs + mem) + TL-UL master (SBA) + JTAG TAP.

module vyges_rv_dbg_tlul
  import tlul_pkg::*;
#(
    parameter int  unsigned NrHarts       = 1,
    parameter int  unsigned BusWidth      = 32,
    parameter int  unsigned DmBaseAddress = 'h00010000,
    parameter logic [31:0]  IdcodeValue   = 32'h1000_0001
) (
    // ── Clocks / resets ──────────────────────────────────────────────
    input  logic                 clk_i,
    input  logic                 rst_ni,

    // ── Debug-chain / scan config ────────────────────────────────────
    input  logic [31:0]          next_dm_addr_i,
    input  logic                 testmode_i,

    // ── CPU debug interface ──────────────────────────────────────────
    output logic                 ndmreset_o,
    input  logic                 ndmreset_ack_i,
    output logic                 dmactive_o,
    output logic [NrHarts-1:0]   debug_req_o,
    input  logic [NrHarts-1:0]   unavailable_i,

    // ── TL-UL slave (regs + mem) ─────────────────────────────────────
    input  tl_h2d_t              regs_tl_d_i,
    output tl_d2h_t              regs_tl_d_o,

    // ── TL-UL master (SBA) ───────────────────────────────────────────
    output tl_h2d_t              sba_tl_h_o,
    input  tl_d2h_t              sba_tl_h_i,

    // ── JTAG TAP physical pins ───────────────────────────────────────
    input  logic                 jtag_tck_i,
    input  logic                 jtag_tms_i,
    input  logic                 jtag_tdi_i,
    output logic                 jtag_tdo_o,
    output logic                 jtag_tdo_oe_o,
    input  logic                 jtag_trst_ni
);

    // ── Internal signals ─────────────────────────────────────────────
    // Pulp dm_top slave port — mark_debug for ILA visibility of the CPU-side
    // fetch handshake into the DM register-file + ROM.
    (* mark_debug = "true", keep = "true" *) logic                   dm_slave_req;
    (* mark_debug = "true", keep = "true" *) logic                   dm_slave_we;
    (* mark_debug = "true", keep = "true" *) logic [BusWidth-1:0]    dm_slave_addr;
    (* mark_debug = "true", keep = "true" *) logic [BusWidth/8-1:0]  dm_slave_be;
    (* mark_debug = "true", keep = "true" *) logic [BusWidth-1:0]    dm_slave_wdata;
    (* mark_debug = "true", keep = "true" *) logic [BusWidth-1:0]    dm_slave_rdata;

    // Pulp dm_top master (SBA) port
    logic                   dm_master_req;
    logic [BusWidth-1:0]    dm_master_add;
    logic                   dm_master_we;
    logic [BusWidth-1:0]    dm_master_wdata;
    logic [BusWidth/8-1:0]  dm_master_be;
    logic                   dm_master_gnt;
    logic                   dm_master_r_valid;
    logic                   dm_master_r_err;
    logic                   dm_master_r_other_err;
    logic [BusWidth-1:0]    dm_master_r_rdata;

    // DMI <-> JTAG glue
    logic                   dmi_rst_n;
    logic                   dmi_req_valid;
    logic                   dmi_req_ready;
    dm::dmi_req_t           dmi_req;
    logic                   dmi_resp_valid;
    logic                   dmi_resp_ready;
    dm::dmi_resp_t          dmi_resp;

    // Hartinfo — default values per pulp convention for Ibex-class harts
    // (2 data regs, 2 scratch CSRs, data access via memory-mapped abstract).
    dm::hartinfo_t [NrHarts-1:0] hartinfo;
    always_comb begin
        for (int unsigned h = 0; h < NrHarts; h++) begin
            hartinfo[h] = '{
                zero1   : '0,
                nscratch: 2,
                zero0   : '0,
                dataaccess: 1'b1,  // data regs at dataaddr, not in CSR space
                datasize: dm::DataCount,
                dataaddr: dm::DataAddr
            };
        end
    end

    // ── TL-UL slave adapter ──────────────────────────────────────────
    vyges_rv_dbg_tlul_slave #(
        .BusWidth(BusWidth)
    ) u_slave_adapter (
        .clk_i,
        .rst_ni,
        // TL-UL side
        .tl_d_i          (regs_tl_d_i),
        .tl_d_o          (regs_tl_d_o),
        // pulp dm_top slave side
        .slave_req_o     (dm_slave_req),
        .slave_we_o      (dm_slave_we),
        .slave_addr_o    (dm_slave_addr),
        .slave_be_o      (dm_slave_be),
        .slave_wdata_o   (dm_slave_wdata),
        .slave_rdata_i   (dm_slave_rdata)
    );

    // ── TL-UL master adapter (SBA) ───────────────────────────────────
    vyges_rv_dbg_tlul_master #(
        .BusWidth(BusWidth)
    ) u_master_adapter (
        .clk_i,
        .rst_ni,
        // pulp dm_top master side
        .master_req_i         (dm_master_req),
        .master_add_i         (dm_master_add),
        .master_we_i          (dm_master_we),
        .master_wdata_i       (dm_master_wdata),
        .master_be_i          (dm_master_be),
        .master_gnt_o         (dm_master_gnt),
        .master_r_valid_o     (dm_master_r_valid),
        .master_r_err_o       (dm_master_r_err),
        .master_r_other_err_o (dm_master_r_other_err),
        .master_r_rdata_o     (dm_master_r_rdata),
        // TL-UL host side
        .tl_h_o          (sba_tl_h_o),
        .tl_h_i          (sba_tl_h_i)
    );

    // ── pulp dm_top core ─────────────────────────────────────────────
    // Source: vyges-ip/pulp-riscv-dbg/rtl/dm_top.sv
    dm_top #(
        .NrHarts       (NrHarts),
        .BusWidth      (BusWidth),
        .DmBaseAddress (DmBaseAddress)
    ) u_dm_top (
        .clk_i,
        .rst_ni,
        .next_dm_addr_i,
        .testmode_i,
        .ndmreset_o,
        .ndmreset_ack_i,
        .dmactive_o,
        .debug_req_o,
        .unavailable_i,
        .hartinfo_i      (hartinfo),

        // Slave — driven by our TL-UL slave adapter
        .slave_req_i     (dm_slave_req),
        .slave_we_i      (dm_slave_we),
        .slave_addr_i    (dm_slave_addr),
        .slave_be_i      (dm_slave_be),
        .slave_wdata_i   (dm_slave_wdata),
        .slave_rdata_o   (dm_slave_rdata),

        // Master (SBA) — drives our TL-UL master adapter
        .master_req_o         (dm_master_req),
        .master_add_o         (dm_master_add),
        .master_we_o          (dm_master_we),
        .master_wdata_o       (dm_master_wdata),
        .master_be_o          (dm_master_be),
        .master_gnt_i         (dm_master_gnt),
        .master_r_valid_i     (dm_master_r_valid),
        .master_r_err_i       (dm_master_r_err),
        .master_r_other_err_i (dm_master_r_other_err),
        .master_r_rdata_i     (dm_master_r_rdata),

        // DMI — driven by JTAG TAP below
        .dmi_rst_ni       (dmi_rst_n),
        .dmi_req_valid_i  (dmi_req_valid),
        .dmi_req_ready_o  (dmi_req_ready),
        .dmi_req_i        (dmi_req),
        .dmi_resp_valid_o (dmi_resp_valid),
        .dmi_resp_ready_i (dmi_resp_ready),
        .dmi_resp_o       (dmi_resp)
    );

    // ── JTAG TAP (standard) ──────────────────────────────────────────
    // Source: vyges-ip/pulp-riscv-dbg/rtl/dmi_jtag.sv
    dmi_jtag #(
        .IdcodeValue (IdcodeValue)
    ) u_dmi_jtag (
        .clk_i,
        .rst_ni,
        .testmode_i,
        .dmi_rst_no      (dmi_rst_n),
        .dmi_req_o       (dmi_req),
        .dmi_req_valid_o (dmi_req_valid),
        .dmi_req_ready_i (dmi_req_ready),
        .dmi_resp_i      (dmi_resp),
        .dmi_resp_ready_o(dmi_resp_ready),
        .dmi_resp_valid_i(dmi_resp_valid),
        .tck_i           (jtag_tck_i),
        .tms_i           (jtag_tms_i),
        .trst_ni         (jtag_trst_ni),
        .td_i            (jtag_tdi_i),
        .td_o            (jtag_tdo_o),
        .tdo_oe_o        (jtag_tdo_oe_o)
    );

endmodule
