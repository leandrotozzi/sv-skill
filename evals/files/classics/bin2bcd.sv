// Copyright (c) 2026 Leandro Tozzi
// All rights reserved
//
// Description:
//   Reference sequential double dabble converter (only used to validate
//   bin2bcd_tb.sv). The start edge captures bin_i; Width iteration edges
//   follow, each adding 3 to every BCD digit above 4 and then shifting
//   {bcd, bin} left by one; the last one drops busy_o and raises done_o for
//   one cycle. Width must be 4 to 32.
`default_nettype none

module bin2bcd #(
    parameter  int Width  = 16,                         // binary input width, 4 to 32
    // Digits of 2**Width - 1 = floor(Width * log10(2)) + 1, as 2**Width is never a
    // power of ten; 30103 / 100000 is close enough to log10(2) for Width up to 32.
    localparam int Digits = Width * 30103 / 100000 + 1
) (
    input  logic                clk_i,    // clock
    input  logic                rst_ni,   // asynchronous reset, active low
    input  logic                start_i,  // start; ignored while busy_o
    input  logic [   Width-1:0] bin_i,    // unsigned binary, sampled on start
    output logic                busy_o,   // conversion in flight
    output logic                done_o,   // one-cycle pulse when busy_o falls
    output logic [4*Digits-1:0] bcd_o     // BCD digits, units in [3:0], held after done_o
);
    if (Width < 4 || Width > 32) begin : gen_bad_width
        $error("bin2bcd: Width must be 4 to 32");
    end

    localparam int CntW = $clog2(Width + 1);  // step counter width

    logic [          CntW-1:0] cnt_q;  // steps left
    logic [4*Digits+Width-1:0] shift_q;  // {bcd, bin}, shifted left 1 per step
    logic [4*Digits+Width-1:0] adj;  // shift_q with every BCD digit above 4 plus 3

    // Add 3 to every digit of 5 or more, so the next shift carries into the digit above.
    always_comb begin
        adj = shift_q;
        for (int d = 0; d < Digits; d++) begin
            if (shift_q[Width+4*d+:4] >= 4'd5) begin
                adj[Width+4*d+:4] = shift_q[Width+4*d+:4] + 4'd3;
            end
        end
    end

    // Start captures bin_i, then Width add-3-and-shift steps.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            busy_o  <= 1'b0;
            done_o  <= 1'b0;
            cnt_q   <= '0;
            shift_q <= '0;
        end else begin
            done_o <= 1'b0;
            if (!busy_o) begin
                if (start_i) begin
                    busy_o  <= 1'b1;
                    cnt_q   <= CntW'(Width);
                    shift_q <= {{(4 * Digits) {1'b0}}, bin_i};
                end
            end else begin
                shift_q <= adj << 1;
                cnt_q   <= cnt_q - 1'b1;
                if (cnt_q == 1) begin
                    busy_o <= 1'b0;
                    done_o <= 1'b1;
                end
            end
        end
    end

    assign bcd_o = shift_q[Width+:4*Digits];
endmodule

`resetall
