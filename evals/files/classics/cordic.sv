// Reference pipelined rotation-mode CORDIC. x/y are Q2.18, z is Q4.20.
// x starts at the inverse CORDIC gain so no correction is needed afterwards.
// Latency: 1 input stage + NumIter iteration stages = 17 cycles.
module cordic (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        valid_i,
    input  logic [15:0] angle_i,
    output logic        valid_o,
    output logic [15:0] cos_o,
    output logic [15:0] sin_o
);
    localparam int NumIter = 16;
    localparam int XyW     = 20;  // Q2.18
    localparam int ZW      = 24;  // Q4.20

    localparam logic signed [XyW-1:0] InvGain = 20'sd159188;  // 0.607252935 * 2**18

    // round(atan(2**-i) * 2**20)
    function automatic logic signed [ZW-1:0] atan_lut(int i);
        case (i)
            0:  atan_lut = 24'sd823550;
            1:  atan_lut = 24'sd486170;
            2:  atan_lut = 24'sd256879;
            3:  atan_lut = 24'sd130396;
            4:  atan_lut = 24'sd65451;
            5:  atan_lut = 24'sd32757;
            6:  atan_lut = 24'sd16383;
            7:  atan_lut = 24'sd8192;
            8:  atan_lut = 24'sd4096;
            9:  atan_lut = 24'sd2048;
            10: atan_lut = 24'sd1024;
            11: atan_lut = 24'sd512;
            12: atan_lut = 24'sd256;
            13: atan_lut = 24'sd128;
            14: atan_lut = 24'sd64;
            default: atan_lut = 24'sd32;
        endcase
    endfunction

    logic                  vld_q [NumIter+1];
    logic signed [XyW-1:0] x_q   [NumIter+1];
    logic signed [XyW-1:0] y_q   [NumIter+1];
    logic signed [ZW-1:0]  z_q   [NumIter+1];

    // Stage 0: load the vector (1/K, 0) and the angle widened to Q4.20.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            vld_q[0] <= 1'b0;
            x_q[0]   <= '0;
            y_q[0]   <= '0;
            z_q[0]   <= '0;
        end else begin
            vld_q[0] <= valid_i;
            x_q[0]   <= InvGain;
            y_q[0]   <= '0;
            z_q[0]   <= {{1{angle_i[15]}}, angle_i, 7'b0};
        end
    end

    for (genvar i = 0; i < NumIter; i++) begin : g_stage
        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                vld_q[i+1] <= 1'b0;
                x_q[i+1]   <= '0;
                y_q[i+1]   <= '0;
                z_q[i+1]   <= '0;
            end else begin
                vld_q[i+1] <= vld_q[i];
                if (!z_q[i][ZW-1]) begin  // z >= 0: rotate counter-clockwise
                    x_q[i+1] <= x_q[i] - (y_q[i] >>> i);
                    y_q[i+1] <= y_q[i] + (x_q[i] >>> i);
                    z_q[i+1] <= z_q[i] - atan_lut(i);
                end else begin
                    x_q[i+1] <= x_q[i] + (y_q[i] >>> i);
                    y_q[i+1] <= y_q[i] - (x_q[i] >>> i);
                    z_q[i+1] <= z_q[i] + atan_lut(i);
                end
            end
        end
    end

    // Round Q2.18 to Q2.14 (add the first dropped bit).
    assign cos_o   = x_q[NumIter][19:4] + 16'(x_q[NumIter][3]);
    assign sin_o   = y_q[NumIter][19:4] + 16'(y_q[NumIter][3]);
    assign valid_o = vld_q[NumIter];
endmodule
