// Copyright (c) 2026 Leandro Tozzi
// All rights reserved
//
// Description:
//   Reference digit-by-digit integer square root (only used to validate
//   isqrt_tb.sv). The start edge captures x_i; Width/2 iteration edges follow,
//   each bringing down two radicand bits and deciding one root bit; the last
//   one drops busy_o and raises done_o for one cycle. Width must be even, >= 4.
`default_nettype none

module isqrt #(
    parameter int Width = 16  // radicand width, even and at least 4
) (
    input  logic               clk_i,    // clock
    input  logic               rst_ni,   // asynchronous reset, active low
    input  logic               start_i,  // start; ignored while busy_o
    input  logic [  Width-1:0] x_i,      // unsigned radicand, sampled on start
    output logic               busy_o,   // computation in flight
    output logic               done_o,   // one-cycle pulse when busy_o falls
    output logic [Width/2-1:0] root_o,   // floor(sqrt(x)), held after done_o
    output logic [  Width/2:0] rem_o     // x - root*root, held after done_o
);
    if (Width < 4 || Width % 2 != 0) begin : gen_bad_width
        $error("isqrt: Width must be even and at least 4");
    end

    localparam int Half = Width / 2;  // root width and step count
    localparam int CntW = $clog2(Half + 1);  // step counter width

    logic [ CntW-1:0] cnt_q;  // steps left
    logic [Width-1:0] x_q;  // radicand, shifted left 2 per step
    logic [ Half-1:0] root_q;  // root bits decided so far
    logic [   Half:0] rem_q;  // partial remainder
    logic [ Half+2:0] trial;  // partial remainder with the next two bits
    logic [ Half+2:0] sub;  // {root, 01}
    logic             fits;  // next root bit is 1

    assign trial = {rem_q, x_q[Width-1-:2]};
    assign sub   = {1'b0, root_q, 2'b01};
    assign fits  = trial >= sub;

    // Start capture, then one root bit per edge.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            busy_o <= 1'b0;
            done_o <= 1'b0;
            cnt_q  <= '0;
            x_q    <= '0;
            root_q <= '0;
            rem_q  <= '0;
        end else begin
            done_o <= 1'b0;
            if (!busy_o) begin
                if (start_i) begin
                    busy_o <= 1'b1;
                    cnt_q  <= CntW'(Half);
                    x_q    <= x_i;
                    root_q <= '0;
                    rem_q  <= '0;
                end
            end else begin
                // trial < sub <= 4*root + 1 keeps the kept remainder within Half+1 bits.
                rem_q  <= fits ? (Half + 1)'(trial - sub) : trial[Half:0];
                root_q <= {root_q[Half-2:0], fits};
                x_q    <= x_q << 2;
                cnt_q  <= cnt_q - 1'b1;
                if (cnt_q == 1) begin
                    busy_o <= 1'b0;
                    done_o <= 1'b1;
                end
            end
        end
    end

    assign root_o = root_q;
    assign rem_o  = rem_q;
endmodule

`resetall
