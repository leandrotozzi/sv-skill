// Reference debounce bank: each bit's output takes the input's value once the
// input has differed from it for CountMax consecutive clock edges.
module debounce_bank #(
    parameter int NumBits  = 8,
    parameter int CountMax = 4
) (
    input  logic               clk_i,
    input  logic               rst_ni,
    input  logic [NumBits-1:0] in_i,
    output logic [NumBits-1:0] out_o
);
    int cnt_q[NumBits];

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            out_o <= '0;
            for (int b = 0; b < NumBits; b++) cnt_q[b] <= 0;
        end else begin
            for (int b = 0; b < NumBits; b++) begin
                if (in_i[b] == out_o[b]) cnt_q[b] <= 0;
                else if (cnt_q[b] == CountMax - 1) begin
                    out_o[b] <= in_i[b];
                    cnt_q[b] <= 0;
                end else cnt_q[b] <= cnt_q[b] + 1;
            end
        end
    end
endmodule
