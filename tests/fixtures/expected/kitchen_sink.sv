// Copyright (c) 2026 ACME Corp
// All rights reserved
//
// Description:
//   Fixture #1: every construct parse.py must anchor.

`default_nettype none

package ks_pkg;
    localparam int unsigned Depth = 4;  // Entries per lane
    typedef logic [7:0] byte_t;
endpackage

interface ks_if;
    logic valid;  // Beat valid
    logic ready;  // TODO: describe
    modport sink(input valid, output ready);
endinterface

module kitchen_sink #(
    parameter int unsigned Lanes = 2,  // Number of lanes
    parameter int unsigned Width = 8   // TODO: describe
) (
    input  logic                             clk_i,         // Clock
    input  logic                             rst_ni,        // TODO: describe
    input  logic      [Lanes-1:0][Width-1:0] data_i,        // TODO: describe
    mask_i,  // Packed lanes
           ks_if.sink                        bus,           // TODO: describe
    output logic      [Width-1:0]            mem_o [Lanes]  // TODO: describe
);
    import ks_pkg::*;

    localparam int unsigned Total = Lanes * Width;  // TODO: describe
    logic [Width-1:0] mem_q                    [Lanes];  // Unpacked storage
    logic             any_w;  // TODO: describe

`ifdef KS_DEBUG
    logic debug_q;
`endif  // KS_DEBUG

    // Register every lane.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        logic tmp;
        if (!rst_ni) begin
            mem_q <= '{default: '0};
        end else begin
            mem_q <= mem_q;
        end
    end

    // TODO: describe
    always_comb begin
        mem_o = mem_q;
    end

    for (genvar g = 0; g < Lanes; g++) begin : gen_lane
        logic lane_q;  // Per-lane flag
        // One buffer per lane.
        ks_buf #(
            .Width(Width)
        ) u_buf (
            .clk_i(clk_i),
            .d_i  (data_i[g]),
            .q_o  ()
        );
    end

    // TODO: describe
    ks_buf u_pos (
        clk_i,
        data_i[0],
    );
    // TODO: describe
    ks_buf u_wild (.*);

    assign any_w = |mask_i;
endmodule

`resetall
