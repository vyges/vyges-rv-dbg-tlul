# vyges-rv-dbg-tlul

TL-UL-wrapped RISC-V Debug Module (RISC-V Debug Spec 0.13). Drop-in debug
support for TL-UL SoCs.

## Module

`vyges_rv_dbg_tlul` wraps `pulp-platform/riscv-dbg` `dm_top` with:

- TL-UL slave (registers + debug memory, 8 KB region)
- TL-UL master (System Bus Access)
- JTAG TAP

Companion adapters:

- `vyges_rv_dbg_tlul_slave` — TL-UL → req/gnt slave adapter (drives
  `dm_top.slave_*`).
- `vyges_rv_dbg_tlul_master` — req/gnt master → TL-UL adapter (carries
  `dm_top.master_*` SBA out to the system xbar).

## Parameters

| Parameter        | Default          | Notes                                     |
|------------------|------------------|-------------------------------------------|
| `NrHarts`        | 1                | Number of harts the DM addresses          |
| `BusWidth`       | 32               | Must equal `top_pkg::TL_DW`               |
| `DmBaseAddress`  | `'h0001_0000`    | System address of the slave window        |
| `IdcodeValue`    | `32'h1000_0001`  | JTAG IDCODE                               |

## Address layout (slave window)

8 KB region split by `addr[11]`:

| Range           | Purpose                                  |
|-----------------|------------------------------------------|
| `base + 0x000`  | DM CSR / control / data / progbuf region |
| `base + 0x800`  | Debug ROM                                |

## Dependencies

- `pulp-riscv-dbg` — debug module core (`dm_top`, `dmi_jtag`, debug ROM).
- `opentitan-tlul` — `tlul_pkg::tl_h2d_t` / `tl_d2h_t` types and
  `tlul_rsp_intg_gen` for the slave's D-channel integrity.

## License

`LICENSE` — Apache-2.0 (Vyges-authored wrapper). Dependent IPs retain
their own licenses.
