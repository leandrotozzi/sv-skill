// Reference ITU-T O.150 PRBS generator: Fibonacci LFSR shifting left, new bit =
// state[Order-1] ^ state[Tap-1]; all ones after reset; load wins over enable.
module lfsr #(
    parameter int Order = 7
) (
    input  logic             clk_i,
    input  logic             rst_ni,
    input  logic             en_i,
    input  logic             load_i,
    input  logic [Order-1:0] seed_i,
    output logic [Order-1:0] state_o,
    output logic             bit_o
);
    localparam int Tap = Order == 7 ? 6 : Order == 15 ? 14 : Order == 23 ? 18 : 28;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) state_o <= '1;
        else if (load_i) state_o <= seed_i;
        else if (en_i) state_o <= {state_o[Order-2:0], state_o[Order-1] ^ state_o[Tap-1]};
    end
    assign bit_o = state_o[Order-1];
endmodule
