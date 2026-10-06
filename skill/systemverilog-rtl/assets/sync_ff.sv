// Copyright (c) 2026 <Company>
// All rights reserved
//
// Description:
//   Synchroniser rank: NumFlops flops (2, or 3 for a fast destination clock)
//   that bring an asynchronous level into clk_i's domain. Width bits are
//   synchronised independently, so use Width > 1 only for unrelated bits or
//   a Gray-coded pointer, never for a binary bus (CDC-002, CDC-003). As a reset synchroniser (RST-002), tie d_i to
//   1 and rst_ni to the incoming reset: q_o falls at once and rises NumFlops
//   clk_i edges after the reset is released.

`default_nettype none

`include "assert_macros.svh"

module sync_ff #(
    parameter int unsigned Width = 1,  // Independent bits synchronised; at least 1
    parameter int unsigned NumFlops = 2,  // Flops in the rank; at least 2
    parameter logic [Width-1:0] ResetValue = '0  // q_o during reset and before the first edge
) (
    input  logic             clk_i,   // Destination clock
    input  logic             rst_ni,  // Asynchronous reset, active-low
    input  logic [Width-1:0] d_i,     // Asynchronous level, from a source-domain flop (CDC-004)
    output logic [Width-1:0] q_o      // d_i in clk_i's domain, NumFlops edges later
);
    // A rank of one flop does not resolve metastability.
    if (NumFlops < 2) begin : gen_num_flops_check
        $error("NumFlops must be at least 2");
    end
    // A zero-width rank has no meaning.
    if (Width < 1) begin : gen_width_check
        $error("Width must be at least 1");
    end

    logic [NumFlops-2:0][Width-1:0] meta_q;  // Stages before the last; stage 0 may go metastable
    logic [Width-1:0] sync_q;  // Last stage, apart from meta_q: a reset never shares data's vector

    // The whole rank resets together; no logic between stages (CDC-001).
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            meta_q <= {(NumFlops - 1) {ResetValue}};
            sync_q <= ResetValue;
        end else begin
            meta_q[0] <= d_i;
            for (int i = 1; i < NumFlops - 1; i++) begin
                meta_q[i] <= meta_q[i-1];
            end
            sync_q <= meta_q[NumFlops-2];
        end
    end

    assign q_o = sync_q;

    // The synchronised output is never X once out of reset (VER-002).
    `ASSERT_KNOWN(SyncKnown_A, q_o)
endmodule

`resetall
