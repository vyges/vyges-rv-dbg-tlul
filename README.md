# vyges-rv-dbg-tlul

TL-UL-wrapped RISC-V Debug Module (RISC-V Debug Spec 0.13). Drop-in debug support for Vyges TL-UL SoCs.

## Usage

In your `soc-spec.yaml`:

```yaml
debug_module:
  ip: vyges-rv-dbg-tlul
  instance: u_dm
  target_cpu: u_ibex
  xbar: xbar_main
  base_address: 0x00010000
  size: 8KB
  jtag:
    idcode: 0x10000001
    tck_pin: "13"
    tms_pin: "14"
    tdi_pin: "15"
    tdo_pin: "16"
  config:
    NrHarts: 1
    BusWidth: 32
```

soc-generator emits the wrapper instantiation, xbar wiring, and JTAG pin mapping.

## Dependencies

- `vyges-ip/pulp-riscv-dbg` — debug module core (`dm_top`, `dmi_jtag`, debug ROM)
- `vyges-ip/opentitan-tlul` — `tlul_pkg::tl_h2d_t` / `tl_d2h_t`

## License

`LICENSE` — Apache-2.0 (Vyges-authored wrapper). Dependent IPs retain their own licenses.
