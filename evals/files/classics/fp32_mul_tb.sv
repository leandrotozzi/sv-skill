// Grader harness for eval 123: checks the fp32 multiplier against an exact
// integer model (24x24 significand product, round to nearest even, subnormal
// inputs as zero, flush to zero below 2**-126 after rounding, overflow to
// infinity at 2**128, quiet NaN 0x7FC00000). Every accepted input must come
// out exactly once, in order, with one fixed latency of 1 to 4 cycles, and
// result_o must match bit for bit. An asynchronous reset mid-burst must
// clear valid_o and drop the inputs in flight. Stimulus: all pairs of special values,
// random bit patterns, exponents at the overflow/underflow edges, constructed
// ties and constructed rounding carries (0xFFFFFF rounding up to 2**24).
module fp32_mul_tb;
    localparam int MinLat = 1;
    localparam int MaxLat = 4;
    localparam logic [31:0] QNaN = 32'h7FC0_0000;

    // Result kinds reported by the model (for the coverage summary).
    localparam int KInexact = 0, KExact = 1, KTie = 2, KOverflow = 3, KFlush = 4,
                   KSpecial = 5, KUpToMin = 6, KNumKinds = 7;

    logic        clk = 1'b0;
    logic        rst_n = 1'b0;
    logic        valid_in = 1'b0;
    logic [31:0] a = '0, b = '0;
    logic        valid_out;
    logic [31:0] result;

    fp32_mul u_dut (
        .clk_i(clk), .rst_ni(rst_n), .valid_i(valid_in), .a_i(a), .b_i(b),
        .valid_o(valid_out), .result_o(result)
    );

    always #5 clk = ~clk;

    initial begin
        #20000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    // Exact model of the prompt's rules.
    function automatic logic [31:0] fmul_model(input logic [31:0] x, input logic [31:0] y,
                                               output int kind);
        logic        s = x[31] ^ y[31];
        int          ex = int'(x[30:23]), ey = int'(y[30:23]);
        bit          x_nan = ex == 255 && x[22:0] != 0, y_nan = ey == 255 && y[22:0] != 0;
        logic [47:0] p;
        logic [24:0] m;
        bit          g, st;
        int          e, e_pre;
        kind = KSpecial;
        if (x_nan || y_nan) return QNaN;
        if ((ex == 255 && ey == 0) || (ex == 0 && ey == 255)) return QNaN;
        if (ex == 255 || ey == 255) return {s, 8'hFF, 23'd0};
        if (ex == 0 || ey == 0) return {s, 31'd0};
        p  = 48'({1'b1, x[22:0]}) * 48'({1'b1, y[22:0]});
        e  = ex + ey - 127;  // biased exponent when p is in [2**46, 2**47)
        st = 0;
        if (p[47]) begin
            st = p[0];
            p  = p >> 1;
            e++;
        end
        e_pre = e;
        m  = {1'b0, p[46:23]};
        g  = p[22];
        st = st | (|p[21:0]);
        kind = !g && !st ? KExact : (g && !st ? KTie : KInexact);
        m = m + 25'(g && (st || m[0]));
        if (m[24]) begin
            m = m >> 1;
            e++;
        end
        if (e >= 255) begin
            kind = KOverflow;
            return {s, 8'hFF, 23'd0};
        end
        if (e <= 0) begin
            kind = KFlush;
            return {s, 31'd0};
        end
        if (e == 1 && e_pre == 0) kind = KUpToMin;
        return {s, 8'(e), m[22:0]};
    endfunction

    // Special operands: zeros, subnormals, extremes of the normal range, ones,
    // infinities, quiet and signalling NaNs.
    logic [31:0] specials [] = '{
        32'h0000_0000, 32'h8000_0000, 32'h0000_0001, 32'h807F_FFFF, 32'h0040_0000,
        32'h0080_0000, 32'h8080_0001, 32'h7F7F_FFFF, 32'hFF7F_FFFF, 32'h3F80_0000,
        32'hBF80_0000, 32'h3F80_0001, 32'h3FFF_FFFF, 32'h4000_0000, 32'h3F00_0000,
        32'h1F80_0000, 32'h5F80_0000, 32'h7F80_0000, 32'hFF80_0000, 32'h7FC0_0000,
        32'hFFC0_0000, 32'h7F80_0001, 32'h7FFF_FFFF, 32'hFFA0_0000
    };

    function automatic logic [31:0] mk(bit s, int e, logic [23:0] sig);
        return {s, 8'(e), sig[22:0]};
    endfunction

    // Exponents ea, eb in 1..254 with ea + eb == sum (sum in 2..508).
    task automatic split_exp(int sum, output int ea, output int eb);
        int lo = sum - 254 > 1 ? sum - 254 : 1;
        int hi = sum - 1 < 254 ? sum - 1 : 254;
        ea = lo + int'($urandom % (hi - lo + 1));
        eb = sum - ea;
    endtask

    // Biased result exponent before rounding: 0 (just below 2**-126), 254
    // (just below 2**128), or anywhere in between.
    function automatic int pick_epre();
        case ($urandom % 4)
            0: return 0;
            1: return 254;
            2: return int'($urandom % 5) - 2 + (($urandom % 2) ? 0 : 254);
            default: return 1 + int'($urandom % 253);
        endcase
    endfunction

    task automatic pick(int n, output logic [31:0] x, output logic [31:0] y);
        int     ea, eb, k;
        longint sa, sb, t, top;
        if (n < specials.size() * specials.size()) begin
            x = specials[n / specials.size()];
            y = specials[n % specials.size()];
            return;
        end
        k = $urandom % 8;
        case (k)
            0: begin  // random bit patterns
                x = $urandom;
                y = $urandom;
            end
            1: begin  // a special against random bits
                x = specials[$urandom % specials.size()];
                y = $urandom;
                if ($urandom % 2) {x, y} = {y, x};
            end
            2, 3: begin  // product exponent around the underflow or overflow edge
                split_exp((k == 2 ? 127 : 381) + int'($urandom % 7) - 3, ea, eb);
                x = mk($urandom % 2, ea, 24'($urandom));
                y = mk($urandom % 2, eb, 24'($urandom));
            end
            4: begin  // ties: lowest set bits of the significands sum to the guard bit
                int ta, tb, epre;
                do begin
                    ta = $urandom % 24;
                    tb = 22 + int'($urandom % 2) - ta;
                end while (tb < 0 || tb > 23);
                sa = longint'({1'b1, 23'($urandom)}) & ~((longint'(1) << ta) - 1) |
                     (longint'(1) << ta);
                sb = longint'({1'b1, 23'($urandom)}) & ~((longint'(1) << tb) - 1) |
                     (longint'(1) << tb);
                epre = pick_epre();
                // The sum assumes no product carry; with one, the exponent is one higher.
                split_exp(epre + 127 > 2 ? epre + 127 : 2, ea, eb);
                x = mk($urandom % 2, ea, 24'(sa));
                y = mk($urandom % 2, eb, 24'(sb));
            end
            5: begin  // rounding carry: significand 0xFFFFFF with guard set rounds up
                // Only reachable without a product carry: (2**24-1)**2 < 2**48 - 2**23.
                int epre = pick_epre();
                top = longint'(1) << 47;
                t = top - (longint'(1) << 22);
                do begin
                    sa = (longint'(1) << 23) + longint'($urandom % (1 << 23));
                    sb = (t + sa - 1) / sa;
                end while (sb >= (longint'(1) << 24) || sa * sb >= top);
                split_exp(epre + 127 > 2 ? epre + 127 : 2, ea, eb);
                x = mk($urandom % 2, ea, 24'(sa));
                y = mk($urandom % 2, eb, 24'(sb));
            end
            default: begin  // ordinary normal numbers
                x = mk($urandom % 2, 64 + int'($urandom % 127), 24'($urandom));
                y = mk($urandom % 2, 64 + int'($urandom % 127), 24'($urandom));
            end
        endcase
    endtask

    typedef struct {
        logic [31:0] x, y, exp;
        int          edge_no;
    } item_t;

    item_t queue_q[$];
    int    errors = 0;
    string first = "";
    int    cycle = 0;
    int    latency = -1;
    int    num_out = 0;
    int    kinds[KNumKinds];

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("cycle %0d: %s", cycle, msg);
        errors++;
    endtask

    task automatic observe();
        if ($isunknown(valid_out)) fail("valid_o unknown");
        else if (valid_out) begin
            if (queue_q.size() == 0) fail("valid_o without a matching input");
            else begin
                item_t it  = queue_q.pop_front();
                int    lat = cycle - it.edge_no + 1;  // valid_i cycle to valid_o cycle
                num_out++;
                if (latency < 0) latency = lat;
                if (lat != latency) fail($sformatf("latency %0d, earlier %0d", lat, latency));
                if (lat < MinLat || lat > MaxLat)
                    fail($sformatf("latency %0d outside %0d..%0d", lat, MinLat, MaxLat));
                if (result !== it.exp)
                    fail($sformatf("%h * %h gave %h, expected %h", it.x, it.y, result, it.exp));
            end
        end
    endtask

    initial begin
        int sent = 0;
        bit did_reset = 0;
        #17 rst_n = 1'b1;
        for (int i = 0; i < 150000; i++) begin
            int phase;
            bit v;
            @(negedge clk);
            observe();
            phase = (i / 400) % 3;
            // phase 0: long back-to-back burst; 1: random bubbles; 2: sparse.
            v = (phase == 0) || (phase == 1 && $urandom % 2 == 0) || ($urandom % 8 == 0);
            valid_in = v;
            if (v) begin
                int kind;
                logic [31:0] exp;
                pick(sent, a, b);
                exp = fmul_model(a, b, kind);
                kinds[kind]++;
                queue_q.push_back('{a, b, exp, cycle + 1});
                sent++;
            end else begin
                a = $urandom;
                b = $urandom;
            end
            // Asynchronous reset once, in the middle of a burst.
            if (!did_reset && i == 60010) begin
                did_reset = 1;
                valid_in = 1'b0;
                #2 rst_n = 1'b0;
                #1 if (valid_out !== 1'b0) fail("valid_o not cleared by reset");
                #4 rst_n = 1'b1;
                queue_q.delete();
            end
            @(posedge clk) cycle++;
        end
        repeat (MaxLat + 10) begin
            @(negedge clk);
            observe();
            valid_in = 1'b0;
            @(posedge clk) cycle++;
        end
        if (queue_q.size() != 0) fail($sformatf("%0d inputs never came out", queue_q.size()));
        $display("fp32_mul: %0d results, latency %0d; inexact %0d exact %0d tie %0d overflow %0d",
                 num_out, latency, kinds[KInexact], kinds[KExact], kinds[KTie],
                 kinds[KOverflow]);
        $display("fp32_mul: flush %0d special %0d rounded up to 2**-126 %0d", kinds[KFlush],
                 kinds[KSpecial], kinds[KUpToMin]);
        if (kinds[KTie] < 1000 || kinds[KOverflow] < 1000 || kinds[KFlush] < 1000 ||
            kinds[KUpToMin] < 100)
            fail("stimulus coverage too low");
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d errors, first at %s", errors, first);
        $finish;
    end
endmodule
