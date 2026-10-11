// Copyright (c) 2026 ACME Corp
// All rights reserved
//
// Description:
//   Saturating up/down event counter. Counts up on inc_i and down on dec_i;
//   both in one cycle leave it unchanged. Holds at 0 and at Max instead of
//   wrapping, and flags each saturated cycle on sat_o.

`default_nettype none

`include "assert_macros.svh"

module sat_counter #(
    parameter int unsigned Width = 8  // Counter width in bits; at least 2
) (
    input  logic             clk_i,    // System clock
    input  logic             rst_ni,   // Asynchronous reset, active-low
    input  logic             inc_i,    // Count up this cycle
    input  logic             dec_i,    // Count down this cycle
    output logic [Width-1:0] count_o,  // Current count, 0 after reset
    output logic             sat_o     // A step was refused at 0 or at Max last cycle
);
    // A 1-bit counter would saturate on every step.
    if (Width < 2) begin : gen_width_check
        $error("Width must be at least 2");
    end

    localparam logic [Width-1:0] Max = '1;  // Largest count

    logic [Width-1:0] count_q, count_d;  // Count register
    logic sat_q, sat_d;  // Saturation flag register

    // Step the count; refuse a step past either end and flag it.
    always_comb begin
        count_d = count_q;
        sat_d   = 1'b0;
        if (inc_i && !dec_i) begin
            if (count_q == Max) begin
                sat_d = 1'b1;
            end else begin
                count_d = count_q + 1'b1;
            end
        end else if (dec_i && !inc_i) begin
            if (count_q == '0) begin
                sat_d = 1'b1;
            end else begin
                count_d = count_q - 1'b1;
            end
        end
    end

    // Count and flag are control state: both reset.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            count_q <= '0;
            sat_q   <= 1'b0;
        end else begin
            count_q <= count_d;
            sat_q   <= sat_d;
        end
    end

    assign count_o = count_q;
    assign sat_o   = sat_q;

    // Outputs are never X out of reset (VER-002).
    `ASSERT_KNOWN(CountKnown_A, count_o)
    `ASSERT_KNOWN(SatKnown_A, sat_o)
endmodule

`resetall
