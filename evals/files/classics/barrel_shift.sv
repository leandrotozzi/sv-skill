// Copyright (c) 2026 <Company>
// All rights reserved
//
// Description:
//   Reference combinational barrel shifter for eval 130 (only used to validate
//   barrel_shift_tb). op_i 0 shifts left, 1 shifts right logically, 2 shifts
//   right arithmetically, 3 rotates right. Built as $clog2(Width) stages, stage
//   s moving the data by 2**s when amt_i[s] is set. Width must be a power of
//   two from 2 to 64.

`default_nettype none

module barrel_shift #(
    parameter int Width = 32  // data width, power of two from 2 to 64
) (
    input  logic [        Width-1:0] data_i,  // value to shift
    input  logic [$clog2(Width)-1:0] amt_i,   // shift or rotate amount
    input  logic [              1:0] op_i,    // 0 sll, 1 srl, 2 sra, 3 ror
    output logic [        Width-1:0] data_o   // shifted value
);
    localparam int Stages = $clog2(Width);  // one stage per amount bit

    if (Width < 2 || Width > 64 || (Width & (Width - 1)) != 0) begin : gen_width_check
        $error("barrel_shift: Width must be a power of two from 2 to 64");
    end

    logic fill;  // bit shifted in from the left by right shifts

    assign fill = (op_i == 2'd2) && data_i[Width-1];

    for (genvar s = 0; s < Stages; s++) begin : gen_stage
        localparam int Shift = 2 ** s;  // distance moved by this stage
        logic [Width-1:0] stage_in;  // output of the previous stage
        logic [Width-1:0] shifted;  // stage input moved by Shift
        logic [Width-1:0] stage_out;  // shifted when amt_i[s] is set

        if (s == 0) begin : gen_first
            assign stage_in = data_i;
        end else begin : gen_next
            assign stage_in = gen_stage[s-1].stage_out;
        end

        // Move the stage input by Shift in the direction op_i selects.
        always_comb begin
            unique case (op_i)
                2'd0:    shifted = {stage_in[Width-Shift-1:0], {Shift{1'b0}}};
                2'd3:    shifted = {stage_in[Shift-1:0], stage_in[Width-1:Shift]};
                default: shifted = {{Shift{fill}}, stage_in[Width-1:Shift]};
            endcase
        end

        assign stage_out = amt_i[s] ? shifted : stage_in;
    end

    assign data_o = gen_stage[Stages-1].stage_out;
endmodule

`resetall
