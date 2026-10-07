// Grader harness for eval 131: checks the fp32 adder against an exact integer
// model (both operands scaled to integers in units of 2**-149, added exactly,
// rounded to nearest even; subnormals kept; overflow to infinity at 2**128;
// canonical quiet NaN 0x7FC00000). Flags: nv_o for a signalling NaN operand or
// an effective inf - inf; of_o (with nx_o) on overflow; nx_o whenever the
// rounded result differs from the exact sum (never on NaN or infinity
// results). sub_i flips b's sign, so (-0) - (+0) is -0 and x - x is +0. An
// input sampled at edge t must give valid_o after edge t+3 and only then;
// sum_o and the flags are compared bit for bit whenever valid_o is 1. An
// asynchronous reset mid-burst must clear valid_o and drop the inputs in
// flight, both for a short pulse between edges and for a reset held across
// edges with valid_i high. Stimulus: all pairs of special values for add and
// sub, random bit patterns, exponents near each other, cancellations,
// constructed ties, subnormal pairs and overflow edges, with valid back to
// back, gapped and sparse. Coverage counters make sure each case was really hit.
module fp32_add_tb;
    localparam int Lat = 3;
    localparam logic [31:0] QNaN = 32'h7FC0_0000;
    localparam int W = 288;  // exact sum: 24-bit significand << 253, plus carry

    localparam int KTie = 0, KSubRes = 1, KCancel0 = 2, KMassive = 3, KOverflow = 4,
                   KInvalid = 5, KNan = 6, KInexact = 7, KNegZero = 8, KNumKinds = 9;

    logic        clk = 1'b0;
    logic        rst_n = 1'b0;
    logic        valid_in = 1'b0;
    logic [31:0] a = '0, b = '0;
    logic        sub = 1'b0;
    logic        valid_out, nv, of, nx;
    logic [31:0] sum;

    fp32_add u_dut (
        .clk_i(clk), .rst_ni(rst_n), .valid_i(valid_in), .a_i(a), .b_i(b), .sub_i(sub),
        .valid_o(valid_out), .sum_o(sum), .nv_o(nv), .of_o(of), .nx_o(nx)
    );

    always #5 clk = ~clk;

    initial begin
        #50000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    int kinds[KNumKinds];

    // Exact model of the prompt's rules. flags = {nv, of, nx}.
    function automatic logic [31:0] fadd_model(input logic [31:0] x, input logic [31:0] y,
                                               input logic op_sub, output logic [2:0] flags);
        logic         sx = x[31], sy = y[31] ^ op_sub, s;
        int           ex = int'(x[30:23]), ey = int'(y[30:23]);
        bit x_nan = ex == 255 && x[22:0] != 0, y_nan = ey == 255 && y[22:0] != 0;
        bit x_inf = ex == 255 && x[22:0] == 0, y_inf = ey == 255 && y[22:0] == 0;
        logic [W-1:0] mx, my, t, rem, half;
        longint       bits;
        int           p, sh;
        flags = 3'b000;
        if (x_nan || y_nan) begin
            kinds[KNan]++;
            flags[2] = (x_nan && !x[22]) || (y_nan && !y[22]);
            if (flags[2]) kinds[KInvalid]++;
            return QNaN;
        end
        if (x_inf && y_inf && sx != sy) begin
            kinds[KInvalid]++;
            flags[2] = 1'b1;
            return QNaN;
        end
        if (x_inf) return {sx, 8'hFF, 23'd0};
        if (y_inf) return {sy, 8'hFF, 23'd0};
        // value = m * 2**-149 exactly
        mx = W'({ex != 0, x[22:0]}) << (ex == 0 ? 0 : ex - 1);
        my = W'({ey != 0, y[22:0]}) << (ey == 0 ? 0 : ey - 1);
        if (sx == sy) begin
            t = mx + my;
            s = sx;
        end else if (mx >= my) begin
            t = mx - my;
            s = sx;
        end else begin
            t = my - mx;
            s = sy;
        end
        if (t == 0) begin
            if (sx != sy && mx != 0) kinds[KCancel0]++;
            if (sx == sy && sx) kinds[KNegZero]++;
            return {sx == sy ? sx : 1'b0, 31'd0};
        end
        p = W - 1;
        while (!t[p]) p--;
        if (sx != sy && (ex > ey ? ex : ey) - (p < 23 ? 1 : p - 22) >= 10) kinds[KMassive]++;
        if (p <= 23) begin  // below 2**-125: exactly representable
            if (p < 23) kinds[KSubRes]++;
            return {s, t[30:0]};
        end
        sh   = p - 23;
        rem  = t & ((W'(1) << sh) - 1);
        half = W'(1) << (sh - 1);
        t    = t >> sh;
        if (rem == half) kinds[KTie]++;
        flags[0] = rem != 0;
        if (flags[0]) kinds[KInexact]++;
        bits = (longint'(sh) << 23) + longint'(t[23:0]) +
               longint'(rem > half || (rem == half && t[0]));
        if (bits >= 64'h7F80_0000) begin
            kinds[KOverflow]++;
            flags = 3'b011;
            return {s, 8'hFF, 23'd0};
        end
        return {s, bits[30:0]};
    endfunction

`ifdef FP32_ADD_TB_DPI_CHECK
    // Validation only (not used by the grader): cross-check the model against
    // the host FPU.
    import "DPI-C" function int unsigned c_fadd(int unsigned x, int unsigned y, int sub,
                                                output int flags);
    int model_checked = 0;
    function automatic void dpi_check(logic [31:0] x, logic [31:0] y, logic op_sub,
                                      logic [31:0] r, logic [2:0] f);
        int          cf;
        int unsigned cr = c_fadd(x, y, int'(op_sub), cf);
        model_checked++;
        if (cr != r || 3'(cf) != f) begin
            $display("MODEL MISMATCH %h %s %h: model %h/%b host %h/%b", x, op_sub ? "-" : "+",
                     y, r, f, cr, 3'(cf));
            $finish;
        end
    endfunction
`endif

    // Special operands: zeros, subnormals, extremes of the normal range, ones,
    // infinities, quiet and signalling NaNs.
    logic [31:0] specials [] = '{
        32'h0000_0000, 32'h8000_0000, 32'h0000_0001, 32'h8000_0001, 32'h007F_FFFF,
        32'h807F_FFFF, 32'h0040_0000, 32'h0080_0000, 32'h8080_0000, 32'h0080_0001,
        32'h7F7F_FFFF, 32'hFF7F_FFFF, 32'h7F7F_FFFE, 32'h7F00_0000, 32'h3F80_0000,
        32'hBF80_0000, 32'h3F80_0001, 32'h3FFF_FFFF, 32'h4000_0000, 32'h3300_0000,
        32'h3380_0000, 32'h7F80_0000, 32'hFF80_0000, 32'h7FC0_0000, 32'hFFC0_0000,
        32'h7FC0_0001, 32'h7F80_0001, 32'hFFA0_0000, 32'h7FBF_FFFF
    };

    function automatic logic [31:0] mk(bit s, int e, logic [22:0] f);
        return {s, 8'(e), f};
    endfunction

    // Significand patterns: random, all ones, all zeros, sparse.
    function automatic logic [22:0] rfrac();
        case ($urandom % 6)
            0: return '1;
            1: return '0;
            2: return 23'(1) << ($urandom % 23);
            3: return ~(23'(1) << ($urandom % 23));
            default: return 23'($urandom);
        endcase
    endfunction

    function automatic int rexp();
        case ($urandom % 5)
            0: return $urandom % 4;          // subnormal and the lowest normals
            1: return 251 + $urandom % 4;    // highest normals
            2: return 120 + $urandom % 16;   // around one
            default: return 1 + $urandom % 254;
        endcase
    endfunction

    function automatic int clampe(int e);
        return e < 0 ? 0 : e > 254 ? 254 : e;
    endfunction

    task automatic pick(int n, output logic [31:0] x, output logic [31:0] y,
                        output logic op_sub);
        int k, ea, d;
        int ns = specials.size();
        if (n < 2 * ns * ns) begin
            x = specials[(n / 2) / ns];
            y = specials[(n / 2) % ns];
            op_sub = n % 2;
            return;
        end
        op_sub = $urandom % 2;
        k = $urandom % 10;
        case (k)
            0: begin  // random bit patterns
                x = $urandom;
                y = $urandom;
            end
            1: begin  // a special against anything
                x = specials[$urandom % ns];
                y = ($urandom % 2) ? $urandom : mk($urandom % 2, rexp(), rfrac());
                if ($urandom % 2) {x, y} = {y, x};
            end
            2, 3: begin  // exponents close together
                ea = rexp();
                d  = int'($urandom % 61) - 30;
                x  = mk($urandom % 2, ea, rfrac());
                y  = mk($urandom % 2, clampe(ea + d), rfrac());
            end
            4: begin  // cancellation: same magnitude, a few low bits changed, effective sub
                ea = rexp();
                x  = mk($urandom % 2, ea, rfrac());
                y  = $urandom % 4 == 0 ? x : x ^ (32'($urandom) >> ($urandom % 32 + 1));
                if ($urandom % 4 == 0) y = y + ($urandom % 2 ? 1 : -1);
                y[31] = x[31] ^ ~op_sub;
                if (y[30:23] == 8'hFF) y[30:23] = 8'hFE;
            end
            5: begin  // tie: b's bits below a's lsb are exactly one half
                ea = 1 + $urandom % 254;
                d  = 1 + $urandom % 25;
                x  = mk($urandom % 2, ea, rfrac());
                y  = mk($urandom % 2, clampe(ea - d), 23'($urandom));
                if (ea - d >= 1 && d <= 23) begin
                    y[22:0] = (y[22:0] >> d << d) | (23'(1) << (d - 1));
                end else if (ea - d >= 1) y[22:0] = '0;  // 2**(ea-d-127) vs a's lsb
            end
            6: begin  // both subnormal or tiny, sometimes both zero
                x = mk($urandom % 2, $urandom % 3, rfrac());
                y = mk($urandom % 2, $urandom % 3, rfrac());
                if ($urandom % 8 == 0) begin
                    x[30:0] = '0;
                    y[30:0] = '0;
                end
            end
            7: begin  // overflow edge
                x = mk($urandom % 2, 252 + $urandom % 3, rfrac());
                y = mk($urandom % 2, 230 + $urandom % 25, rfrac());
                y[31] = x[31] ^ op_sub ^ ($urandom % 4 == 0);
            end
            default: begin  // independent operands, interesting exponents
                x = mk($urandom % 2, rexp(), rfrac());
                y = mk($urandom % 2, rexp(), rfrac());
            end
        endcase
        if ($urandom % 2) {x, y} = {y, x};
    endtask

    typedef struct {
        logic [31:0] x, y, exp;
        logic        op_sub;
        logic [2:0]  flags;
        int          edge_no;
    } item_t;

    item_t queue_q[$];
    int    errors = 0;
    string first = "";
    int    cycle = 0;
    int    num_out = 0;
    int    sent = 0;
    bit    drop = 0;  // set by the reset task: discard everything in flight

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("cycle %0d: %s", cycle, msg);
        errors++;
    endtask

    // Sample what the DUT sees at each edge.
    always @(posedge clk) begin
        cycle++;
        if (rst_n && valid_in === 1'b1) begin
            logic [2:0]  f;
            logic [31:0] r;
            r = fadd_model(a, b, sub, f);
`ifdef FP32_ADD_TB_DPI_CHECK
            dpi_check(a, b, sub, r, f);
`endif
            queue_q.push_back('{a, b, r, sub, f, cycle});
            sent++;
        end
    end

    task automatic observe();
        if ($isunknown(valid_out)) fail("valid_o unknown");
        else if (queue_q.size() > 0 && queue_q[0].edge_no == cycle - Lat) begin
            item_t it = queue_q.pop_front();
            if (valid_out !== 1'b1)
                fail($sformatf("no valid_o %0d edges after the input edge", Lat));
            else begin
                num_out++;
                if (sum !== it.exp || {nv, of, nx} !== it.flags)
                    fail($sformatf("%h %s %h gave %h nv/of/nx %b%b%b, expected %h %b", it.x,
                                   it.op_sub ? "-" : "+", it.y, sum, nv, of, nx, it.exp,
                                   it.flags));
            end
        end else if (valid_out !== 1'b0)
            fail($sformatf("valid_o without an input sampled %0d edges earlier", Lat));
    endtask

    initial begin
        int  total = 0;
        int  num_resets = 0;
        #3 if (valid_out !== 1'b0) fail("valid_o not 0 in reset");
        #14 rst_n = 1'b1;
        for (int i = 0; i < 800000; i++) begin
            int phase;
            bit v;
            @(negedge clk);
            observe();
            phase = (i / 300) % 3;
            // phase 0: back-to-back burst; 1: random bubbles; 2: sparse.
            v = (phase == 0) || (phase == 1 && $urandom % 2 == 0) || ($urandom % 8 == 0);
            valid_in = v;
            if (v) begin
                pick(total, a, b, sub);
                total++;
            end else begin
                a = $urandom;
                b = $urandom;
                sub = $urandom % 2;
            end
            // Asynchronous reset in the middle of a burst: first a short pulse
            // between two edges, later one held across two edges with valid_i high.
            if (i == 300010 || i == 500010) begin
                num_resets++;
                #1 rst_n = 1'b0;
                #1 if (valid_out !== 1'b0) fail("valid_o not cleared by reset");
                queue_q.delete();
                if (i == 300010) #1 rst_n = 1'b1;
                else begin
                    valid_in = 1'b1;
                    #20 if (valid_out !== 1'b0) fail("valid_o not held low in reset");
                    #1 rst_n = 1'b1;
                end
                #1 if (valid_out !== 1'b0) fail("valid_o set right after reset");
            end
            @(posedge clk);
        end
        repeat (Lat + 10) begin
            @(negedge clk);
            observe();
            valid_in = 1'b0;
            @(posedge clk);
        end
        if (queue_q.size() != 0) fail($sformatf("%0d inputs never came out", queue_q.size()));
        $display("fp32_add: %0d results; tie %0d subnormal %0d x-x %0d -0 %0d massive %0d",
                 num_out, kinds[KTie], kinds[KSubRes], kinds[KCancel0], kinds[KNegZero],
                 kinds[KMassive]);
        $display("fp32_add: overflow %0d invalid %0d nan %0d inexact %0d", kinds[KOverflow],
                 kinds[KInvalid], kinds[KNan], kinds[KInexact]);
`ifdef FP32_ADD_TB_DPI_CHECK
        $display("fp32_add: model checked against host on %0d inputs", model_checked);
`endif
        if (num_resets != 2) fail("harness: resets not applied");
        if (num_out < 400000 || kinds[KTie] < 1000 || kinds[KSubRes] < 1000 ||
            kinds[KCancel0] < 1000 || kinds[KNegZero] < 200 || kinds[KMassive] < 1000 ||
            kinds[KOverflow] < 1000 || kinds[KInvalid] < 500)
            fail("stimulus coverage too low");
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d errors, first at %s", errors, first);
        $finish;
    end
endmodule
