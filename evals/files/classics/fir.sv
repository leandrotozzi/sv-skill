// Reference for eval 103: FIR filter, behavioural direct form (same output as
// the transposed form). On each accepted sample the full-precision sum
// Coeffs[0]*x[n] + ... + Coeffs[NumTaps-1]*x[n-NumTaps+1] is registered.
module fir #(
    parameter int DataWidth = 16,
    parameter int CoeffWidth = 16,
    parameter int NumTaps = 8,
    parameter logic [NumTaps*CoeffWidth-1:0] Coeffs = {
        // taps 7 .. 0: -256, 512, 2048, 6144, 8192, 3072, 1024, -512
        -16'sd256, 16'sd512, 16'sd2048, 16'sd6144,
        16'sd8192, 16'sd3072, 16'sd1024, -16'sd512
    },
    localparam int OutWidth = DataWidth + CoeffWidth + $clog2(NumTaps)
) (
    input  logic                clk_i,
    input  logic                rst_ni,
    input  logic                valid_i,
    input  logic [DataWidth-1:0] data_i,
    output logic                valid_o,
    output logic [OutWidth-1:0] data_o
);
    // x_q[k] holds x[n-k-1] (the k+1-th previous sample); 0 after reset.
    logic [NumTaps-2:0][DataWidth-1:0] x_q;
    logic signed [OutWidth-1:0] sum;

    always_comb begin
        sum = OutWidth'($signed(data_i)) * OutWidth'($signed(Coeffs[0+:CoeffWidth]));
        for (int k = 1; k < NumTaps; k++) begin
            sum += OutWidth'($signed(x_q[k-1])) * OutWidth'($signed(Coeffs[k*CoeffWidth+:CoeffWidth]));
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            x_q     <= '0;
            valid_o <= 1'b0;
            data_o  <= '0;
        end else begin
            valid_o <= valid_i;
            if (valid_i) begin
                x_q[0] <= data_i;
                for (int k = 1; k < NumTaps - 1; k++) x_q[k] <= x_q[k-1];
                data_o <= sum;
            end
        end
    end
endmodule
