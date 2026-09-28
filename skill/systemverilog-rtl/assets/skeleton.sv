// Copyright (c) 2026 <Company>
// All rights reserved
//
// Description:
//   Canonical module skeleton: registered valid/data stage with an enable.
//   Copy it, rename the module and file together, and replace the logic.

`default_nettype none

`include "assert_macros.svh"

module skeleton #(
    parameter int unsigned Width = 8  // Payload width in bits; at least 1
) (
    input  logic             clk_i,    // System clock
    input  logic             rst_ni,   // Asynchronous reset, active-low
    input  logic             valid_i,  // Payload on data_i is valid this cycle
    input  logic [Width-1:0] data_i,   // Payload in
    output logic             valid_o,  // Payload on data_o is valid this cycle
    output logic [Width-1:0] data_o    // Payload out, one cycle after data_i
);
    // Width must be positive: a zero-width payload has no meaning.
    if (Width < 1) begin : gen_width_check
        $error("Width must be at least 1");
    end

    logic valid_q, valid_d;  // Output valid register
    logic [Width-1:0] data_q, data_d;  // Output payload register

    // Load the payload on a valid input; hold it otherwise.
    always_comb begin
        valid_d = valid_i;
        data_d  = data_q;
        if (valid_i) begin
            data_d = data_i;
        end
    end

    // Valid is control and is reset; the payload is qualified by it and is not.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_q <= 1'b0;
        end else begin
            valid_q <= valid_d;
        end
    end

    // Payload register, no reset (RST-004).
    always_ff @(posedge clk_i) begin
        data_q <= data_d;
    end

    assign valid_o = valid_q;
    assign data_o  = data_q;

    // Outputs are never X once out of reset (VER-002).
    `ASSERT_KNOWN(ValidKnown_A, valid_o)
    `ASSERT_KNOWN(DataKnown_A, data_o)
endmodule

`resetall
