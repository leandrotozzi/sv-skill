// Reference for eval 10 (only used to validate edge_detect_tb).
module TopModule (
    input  logic       clk,
    input  logic       reset,
    input  logic [7:0] in,
    output logic [7:0] out
);
    logic [7:0] prev;
    always_ff @(posedge clk) begin
        if (reset) begin
            prev <= '0;
            out  <= '0;
        end else begin
            prev <= in;
            out  <= in & ~prev;
        end
    end
endmodule
