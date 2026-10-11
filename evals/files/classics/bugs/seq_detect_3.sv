// Reference for eval 101: Moore FSM detecting 1011 with overlap.
// The state is the longest suffix of the input that is a prefix of 1011.
// Planted bug 3: resets as if a 1 was seen.
module seq_detect (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic bit_i,
    output logic detect_o
);
    localparam logic [2:0] SIdle = 3'd0;  // no useful suffix
    localparam logic [2:0] S1 = 3'd1;  // ...1
    localparam logic [2:0] S10 = 3'd2;  // ...10
    localparam logic [2:0] S101 = 3'd3;  // ...101
    localparam logic [2:0] S1011 = 3'd4;  // ...1011: match

    logic [2:0] state_q, state_d;

    always_comb begin
        case (state_q)
            SIdle:   state_d = bit_i ? S1 : SIdle;
            S1:      state_d = bit_i ? S1 : S10;
            S10:     state_d = bit_i ? S101 : SIdle;
            S101:    state_d = bit_i ? S1011 : S10;
            S1011:   state_d = bit_i ? S1 : S10;  // overlap: "1" or "10" carries over
            default: state_d = SIdle;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) state_q <= S1;
        else state_q <= state_d;
    end

    assign detect_o = (state_q == S1011);
endmodule
