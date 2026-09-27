// Copyright (c) 2026 ACME Corp
// All rights reserved
//
// Description:
//   Registers a payload for one cycle and drives it out through a second
//   flop stage, so both input and output are registered.

`default_nettype none

module reg_byte #(
    parameter int unsigned Width = 8  // Payload width in bits
) (
    input  logic             clk_i,   // System clock
    input  logic             rst_ni,  // Asynchronous reset, active-low
    input  logic [Width-1:0] d_i,     // Payload in
    output logic [Width-1:0] q_o      // Payload, two cycles later
);
    logic [Width-1:0] q_q;  // First-stage register

    // Capture the payload.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            q_q <= '0;
        end else begin
            q_q <= d_i;
        end
    end

    // Second stage keeps the output registered.
    prim_flop #(
        .Width(Width)
    ) u_out (
        .clk_i(clk_i),
        .d_i  (q_q),
        .q_o  (q_o)
    );
endmodule

`resetall
