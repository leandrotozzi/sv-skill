// Reference pipelined fp32 adder (only used to validate fp32_add_tb.sv).
// The inputs are registered; stage 1 decodes, orders the operands by
// magnitude and aligns the smaller one (guard, round, sticky); stage 2 adds or
// subtracts and normalises; stage 3 rounds to nearest even and packs into the
// output registers. An input sampled at edge t is out after edge t+3.
module fp32_add (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        valid_i,
    input  logic [31:0] a_i,
    input  logic [31:0] b_i,
    input  logic        sub_i,
    output logic        valid_o,
    output logic [31:0] sum_o,
    output logic        nv_o,
    output logic        of_o,
    output logic        nx_o
);
    localparam logic [31:0] QNaN = 32'h7FC0_0000;

    // ---------------- Input registers ----------------
    logic        v0_q, sub0_q;
    logic [31:0] a0_q, b0_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) v0_q <= 1'b0;
        else v0_q <= valid_i;
    end

    always_ff @(posedge clk_i) begin
        a0_q   <= a_i;
        b0_q   <= b_i;
        sub0_q <= sub_i;
    end

    // ---------------- Stage 1: decode, order, align ----------------
    logic        sa, sb, a_nan, b_nan, a_inf, b_inf, a_snan, b_snan, swap;
    logic [7:0]  ea, eb, e_big, e_small, d;
    logic [23:0] ma, mb;
    logic [26:0] small_al;

    always_comb begin
        sa     = a0_q[31];
        sb     = b0_q[31] ^ sub0_q;
        a_nan  = a0_q[30:23] == 8'hFF && a0_q[22:0] != 0;
        b_nan  = b0_q[30:23] == 8'hFF && b0_q[22:0] != 0;
        a_inf  = a0_q[30:23] == 8'hFF && a0_q[22:0] == 0;
        b_inf  = b0_q[30:23] == 8'hFF && b0_q[22:0] == 0;
        a_snan = a_nan && !a0_q[22];
        b_snan = b_nan && !b0_q[22];
        ea     = a0_q[30:23] == 0 ? 8'd1 : a0_q[30:23];
        eb     = b0_q[30:23] == 0 ? 8'd1 : b0_q[30:23];
        ma     = {a0_q[30:23] != 0, a0_q[22:0]};
        mb     = {b0_q[30:23] != 0, b0_q[22:0]};
        swap   = b0_q[30:0] > a0_q[30:0];
        e_big  = swap ? eb : ea;
        e_small = swap ? ea : eb;
        d      = e_big - e_small;
        small_al = {swap ? ma : mb, 3'b000};
        if (d >= 27) small_al = {26'd0, |small_al};
        else begin
            logic [26:0] lost;
            lost     = small_al & ((27'd1 << d) - 1);
            small_al = (small_al >> d) | 27'(|lost);
        end
    end

    logic        v1_q, s1_q, eff_sub1_q, spec1_q, nv1_q;
    logic [31:0] spec_res1_q;
    logic [7:0]  e1_q;
    logic [26:0] big1_q, small1_q;
    logic        zsign1_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) v1_q <= 1'b0;
        else v1_q <= v0_q;
    end

    always_ff @(posedge clk_i) begin
        s1_q       <= swap ? sb : sa;
        eff_sub1_q <= sa != sb;
        zsign1_q   <= sa & sb;
        e1_q       <= e_big;
        big1_q     <= {swap ? mb : ma, 3'b000};
        small1_q   <= small_al;
        nv1_q      <= a_snan || b_snan || (a_inf && b_inf && sa != sb);
        spec1_q    <= a_nan || b_nan || a_inf || b_inf;
        if (a_nan || b_nan || (a_inf && b_inf && sa != sb)) spec_res1_q <= QNaN;
        else if (a_inf) spec_res1_q <= {sa, 8'hFF, 23'd0};
        else spec_res1_q <= {sb, 8'hFF, 23'd0};
    end

    // ---------------- Stage 2: add, normalise ----------------
    logic [27:0] raw;
    logic [26:0] norm;
    logic [8:0]  e_norm;
    int          lz;

    always_comb begin
        raw    = eff_sub1_q ? {1'b0, big1_q} - {1'b0, small1_q}
                            : {1'b0, big1_q} + {1'b0, small1_q};
        e_norm = {1'b0, e1_q};
        if (raw[27]) begin
            norm   = raw[27:1] | 27'(raw[0]);
            e_norm = e_norm + 1;
        end else begin
            lz = 0;
            for (int i = 26; i >= 0; i--) begin
                if (raw[i]) break;
                lz++;
            end
            if (lz > int'(e1_q) - 1) lz = int'(e1_q) - 1;  // stop at the subnormal exponent
            norm   = raw[26:0] << lz;
            e_norm = e_norm - 9'(lz);
        end
    end

    logic        v2_q, s2_q, spec2_q, nv2_q, zero2_q;
    logic [31:0] spec_res2_q;
    logic [26:0] m2_q;
    logic [8:0]  e2_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) v2_q <= 1'b0;
        else v2_q <= v1_q;
    end

    always_ff @(posedge clk_i) begin
        zero2_q     <= raw == 0;
        s2_q        <= raw == 0 ? zsign1_q : s1_q;
        spec2_q     <= spec1_q;
        nv2_q       <= nv1_q;
        spec_res2_q <= spec_res1_q;
        m2_q        <= norm;
        e2_q        <= e_norm;
    end

    // ---------------- Stage 3: round, pack ----------------
    logic [31:0] res;
    logic        nv, of, nx, up;
    logic [33:0] packed_mag;

    always_comb begin
        nv = 1'b0;
        of = 1'b0;
        nx = 1'b0;
        if (spec2_q) begin
            res = spec_res2_q;
            nv  = nv2_q;
        end else if (zero2_q) res = {s2_q, 31'd0};
        else begin
            nx = m2_q[2] | m2_q[1] | m2_q[0];
            up = m2_q[2] & (m2_q[1] | m2_q[0] | m2_q[3]);
            // (e - 1) << 23 plus the significand with its hidden bit: a subnormal has
            // e = 1 and no hidden bit, a rounding carry bumps the exponent by itself.
            packed_mag = (34'(e2_q - 1) << 23) + 34'(m2_q[26:3]) + 34'(up);
            if (packed_mag >= 34'h7F80_0000) begin
                res = {s2_q, 8'hFF, 23'd0};
                of  = 1'b1;
                nx  = 1'b1;
            end else res = {s2_q, packed_mag[30:0]};
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) valid_o <= 1'b0;
        else valid_o <= v2_q;
    end

    always_ff @(posedge clk_i) begin
        sum_o <= res;
        nv_o  <= nv;
        of_o  <= of;
        nx_o  <= nx;
    end
endmodule
