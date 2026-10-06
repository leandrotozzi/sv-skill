// Copyright (c) 2026 sv-skill evals
// All rights reserved
//
// Description:
//   Reference for eval 127: CIC decimator, Stages integrators then Stages
//   combs (differential delay 1), all wrapping at OutWidth. The integrators
//   chain combinationally into their registers on each accepted input; on
//   every Rate-th input the comb chain is evaluated in the same cycle and the
//   result registered, so valid_o pulses one cycle after that input.
`default_nettype none

module cic_decim #(
    parameter  int Stages   = 3,                               // integrator/comb pairs, 1 to 5
    parameter  int Rate     = 8,                               // decimation, power of two 2 to 64
    parameter  int InWidth  = 12,                              // input sample width
    localparam int OutWidth = InWidth + Stages * $clog2(Rate)  // full-precision output width
) (
    input  logic                clk_i,    // clock
    input  logic                rst_ni,   // asynchronous reset, active low
    input  logic                valid_i,  // data_i is a new sample
    input  logic [ InWidth-1:0] data_i,   // signed input sample
    output logic                valid_o,  // one-cycle pulse per Rate inputs
    output logic [OutWidth-1:0] data_o    // signed output, held between pulses
);
    if (Stages < 1 || Stages > 5) begin : gen_bad_stages
        $error("cic_decim: Stages must be 1 to 5");
    end
    if (Rate < 2 || Rate > 64 || (Rate & (Rate - 1)) != 0) begin : gen_bad_rate
        $error("cic_decim: Rate must be a power of two from 2 to 64");
    end

    localparam int CntWidth = $clog2(Rate);  // input counter width

    logic [  Stages-1:0][OutWidth-1:0] integ_q;  // integrator values
    logic [  Stages-1:0][OutWidth-1:0] integ_d;  // integrator values after this input
    logic [  Stages-1:0][OutWidth-1:0] comb_q;  // previous input of each comb
    logic [  Stages-1:0][OutWidth-1:0] comb_d;  // current input of each comb
    logic [OutWidth-1:0]               comb_out;  // output of the last comb
    logic [CntWidth-1:0]               cnt_q;  // accepted inputs modulo Rate
    logic                              last_in;  // this input is the Rate-th

    // Integrator chain: stage 0 adds the sign-extended input.
    assign integ_d[0] = integ_q[0] + OutWidth'($signed(data_i));
    for (genvar s = 1; s < Stages; s++) begin : gen_integ
        assign integ_d[s] = integ_q[s] + integ_d[s-1];
    end

    // Comb chain: each comb subtracts its previous input.
    assign comb_d[0] = integ_d[Stages-1];
    for (genvar s = 1; s < Stages; s++) begin : gen_comb
        assign comb_d[s] = comb_d[s-1] - comb_q[s-1];
    end
    assign comb_out = comb_d[Stages-1] - comb_q[Stages-1];

    assign last_in  = valid_i && cnt_q == CntWidth'(Rate - 1);

    // Integrators step on every input, combs and output on every Rate-th one.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            integ_q <= '0;
            comb_q  <= '0;
            cnt_q   <= '0;
            valid_o <= 1'b0;
            data_o  <= '0;
        end else begin
            valid_o <= last_in;
            if (valid_i) begin
                integ_q <= integ_d;
                cnt_q   <= cnt_q + 1'b1;
            end
            if (last_in) begin
                comb_q <= comb_d;
                data_o <= comb_out;
            end
        end
    end
endmodule

`resetall
