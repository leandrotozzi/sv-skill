// Reference pipelined fp32 multiplier (only used to validate fp32_mul_tb.sv).
// Stage 1 decodes the operands and forms the 48-bit significand product;
// stage 2 normalises, rounds to nearest even and handles range. Latency 2.
// Subnormal inputs are zeros, results below 2**-126 flush to zero.
module fp32_mul (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        valid_i,
    input  logic [31:0] a_i,
    input  logic [31:0] b_i,
    output logic        valid_o,
    output logic [31:0] result_o
);
    localparam logic [31:0] QNaN = 32'h7FC0_0000;

    // Stage 1
    logic        a_zero, b_zero, a_inf, b_inf, a_nan, b_nan;
    assign a_zero = a_i[30:23] == 8'd0;
    assign b_zero = b_i[30:23] == 8'd0;
    assign a_inf  = a_i[30:23] == 8'hFF && a_i[22:0] == 23'd0;
    assign b_inf  = b_i[30:23] == 8'hFF && b_i[22:0] == 23'd0;
    assign a_nan  = a_i[30:23] == 8'hFF && a_i[22:0] != 23'd0;
    assign b_nan  = b_i[30:23] == 8'hFF && b_i[22:0] != 23'd0;

    logic        v1_q, s1_q, nan1_q, inf1_q, zero1_q;
    logic [9:0]  e1_q;   // ea + eb, biased twice
    logic [47:0] p1_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            v1_q    <= 1'b0;
            s1_q    <= 1'b0;
            nan1_q  <= 1'b0;
            inf1_q  <= 1'b0;
            zero1_q <= 1'b0;
            e1_q    <= '0;
            p1_q    <= '0;
        end else begin
            v1_q    <= valid_i;
            s1_q    <= a_i[31] ^ b_i[31];
            nan1_q  <= a_nan | b_nan | (a_inf & b_zero) | (a_zero & b_inf);
            inf1_q  <= a_inf | b_inf;
            zero1_q <= a_zero | b_zero;
            e1_q    <= {2'b0, a_i[30:23]} + {2'b0, b_i[30:23]};
            p1_q    <= {1'b1, a_i[22:0]} * {1'b1, b_i[22:0]};
        end
    end

    // Stage 2: product in [2**46, 2**48); value = p * 2**(e1 - 300).
    logic [23:0] mant;
    logic        guard, sticky;
    logic [24:0] mant_r;
    logic signed [11:0] exp_r;
    logic [31:0] res;

    always_comb begin
        if (p1_q[47]) begin
            mant   = p1_q[47:24];
            guard  = p1_q[23];
            sticky = |p1_q[22:0];
            exp_r  = $signed({2'b0, e1_q}) - 12'sd126;
        end else begin
            mant   = p1_q[46:23];
            guard  = p1_q[22];
            sticky = |p1_q[21:0];
            exp_r  = $signed({2'b0, e1_q}) - 12'sd127;
        end
        mant_r = {1'b0, mant} + 25'(guard & (sticky | mant[0]));
        if (mant_r[24]) exp_r = exp_r + 12'sd1;  // 0xFFFFFF rounded up to 2**24
        if (nan1_q)          res = QNaN;
        else if (inf1_q)     res = {s1_q, 8'hFF, 23'd0};
        else if (zero1_q)    res = {s1_q, 31'd0};
        else if (exp_r > 254) res = {s1_q, 8'hFF, 23'd0};
        else if (exp_r < 1)  res = {s1_q, 31'd0};
        else res = {s1_q, exp_r[7:0], mant_r[24] ? 23'd0 : mant_r[22:0]};
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            valid_o  <= 1'b0;
            result_o <= '0;
        end else begin
            valid_o  <= v1_q;
            result_o <= res;
        end
    end
endmodule
