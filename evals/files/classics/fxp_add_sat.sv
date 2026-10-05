// Reference for eval 104: registered saturating signed Q(IntBits).(FracBits) add.
module fxp_add_sat #(
    parameter int IntBits = 4,
    parameter int FracBits = 12,
    localparam int Width = IntBits + FracBits
) (
    input  logic             clk_i,
    input  logic             rst_ni,
    input  logic [Width-1:0] a_i,
    input  logic [Width-1:0] b_i,
    output logic [Width-1:0] sum_o,
    output logic             sat_o
);
    localparam logic signed [Width:0] Max = (Width + 1)'(2 ** (Width - 1) - 1);
    localparam logic signed [Width:0] Min = -(Width + 1)'(2 ** (Width - 1));

    logic signed [Width:0] exact;  // one extra bit: never overflows
    assign exact = $signed({a_i[Width-1], a_i}) + $signed({b_i[Width-1], b_i});

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            sum_o <= '0;
            sat_o <= 1'b0;
        end else if (exact > Max) begin
            sum_o <= Max[Width-1:0];
            sat_o <= 1'b1;
        end else if (exact < Min) begin
            sum_o <= Min[Width-1:0];
            sat_o <= 1'b1;
        end else begin
            sum_o <= exact[Width-1:0];
            sat_o <= 1'b0;
        end
    end
endmodule
