// Copyright (c) 2026 <Company>
// All rights reserved
//
// Description:
//   Assertion macros for synthesizable RTL (VER-001). Copy this file next to
//   the RTL if the project has none of its own. Checks run in simulation and
//   formal; synthesis tools define SYNTHESIS and see nothing.

`ifndef ASSERT_MACROS_SVH
`define ASSERT_MACROS_SVH

`ifndef SYNTHESIS

// Concurrent assertion, clocked on clk and disabled while rst_n is low or
// unknown. Written this way, not as `!rst_n`, so Verilator does not see the
// reset used synchronously (SYNCASYNCNET, RST-005).
`define ASSERT(name, prop, clk = clk_i, rst_n = rst_ni) \
    /* verilator lint_off SYNCASYNCNET */ \
    name : assert property (@(posedge clk) disable iff ($isunknown(rst_n) || !rst_n) (prop)) \
    else $error("assertion %s failed", `"name`"); \
    /* verilator lint_on SYNCASYNCNET */

// A signal is never X or Z outside reset (VER-002).
`define ASSERT_KNOWN(name, sig, clk = clk_i, rst_n = rst_ni) \
    `ASSERT(name, !$isunknown(sig), clk, rst_n)

// Checked once at time zero, e.g. on parameters.
`define ASSERT_INIT(name, prop) \
    initial begin : name \
        assert (prop) else $error("assertion %s failed", `"name`"); \
    end

`else

`define ASSERT(name, prop, clk = clk_i, rst_n = rst_ni)
`define ASSERT_KNOWN(name, sig, clk = clk_i, rst_n = rst_ni)
`define ASSERT_INIT(name, prop)

`endif  // SYNTHESIS

`endif  // ASSERT_MACROS_SVH
