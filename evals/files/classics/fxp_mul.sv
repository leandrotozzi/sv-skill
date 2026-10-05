// Reference for eval 105: registered Q(IntBits).(FracBits) multiply, round to
// nearest with ties toward +infinity, then saturate.
module fxp_mul #(
    parameter int IntBits = 1,
    parameter int FracBits = 15,
    localparam int Width = IntBits + FracBits
) (
    input  logic             clk_i,
    input  logic             rst_ni,
    input  logic [Width-1:0] a_i,
    input  logic [Width-1:0] b_i,
    output logic [Width-1:0] prod_o,
    output logic             sat_o
);
    localparam int PW = 2 * Width + 1;  // exact product plus rounding never overflows
    localparam logic signed [PW-1:0] Max = PW'(2 ** (Width - 1) - 1);
    localparam logic signed [PW-1:0] Min = -PW'(2 ** (Width - 1));

    logic signed [PW-1:0] exact, rounded;
    assign exact = PW'($signed(a_i)) * PW'($signed(b_i));
    assign rounded = (exact + PW'(2 ** (FracBits - 1))) >>> FracBits;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            prod_o <= '0;
            sat_o  <= 1'b0;
        end else if (rounded > Max) begin
            prod_o <= Max[Width-1:0];
            sat_o  <= 1'b1;
        end else if (rounded < Min) begin
            prod_o <= Min[Width-1:0];
            sat_o  <= 1'b1;
        end else begin
            prod_o <= rounded[Width-1:0];
            sat_o  <= 1'b0;
        end
    end
endmodule
