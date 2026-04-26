# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Vyges
#
# Slave-port d_data sample-timing regression for vyges_rv_dbg_tlul_slave.
#
# Verilator is the supported simulator (cocotb 1.9+).
#
# Usage:
#   make                  # run the test
#   make WAVES=fst        # FST waveform output
#   make clean            # wipe sim_build/

SIM           ?= verilator
TOPLEVEL_LANG ?= verilog
TOPLEVEL      ?= tb_slave_timing
MODULE        ?= test_slave_timing

# Allow the wrapper-IP path to be overridden when the test directory is
# vendored into a different layout.
DBG_TLUL ?= ../..

VERILOG_SOURCES := \
    $(PWD)/stubs.sv \
    $(DBG_TLUL)/rtl/vyges_rv_dbg_tlul_slave.sv \
    $(PWD)/tb_slave_timing.sv

EXTRA_ARGS += --trace --trace-structs -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM

include $(shell cocotb-config --makefiles)/Makefile.sim
