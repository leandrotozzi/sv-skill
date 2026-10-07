// Grader harness for eval 133: checks systolic_mm against the prompt at
// N/DataW/AccW = 2/4/10 (results wrap), 4/8/32 and 8/8/20. Each matrix has its
// own K (1 most often, up to 200, plus K = 1024 with all-minimum and with
// extreme operands); beats come back to back (in_valid_i always high), with
// random gaps, or sparsely, and data is held while in_ready_o is low, with
// garbage on the inputs while in_valid_i is low. Only beats that transfer
// (in_valid_i && in_ready_o) count. Every matrix must give exactly one
// out_valid_o cycle within 3N + 2 cycles of its last beat's transfer, in
// order, with c_o equal to the exact signed product sum modulo 2**AccW, and
// c_o must hold until the next out_valid_o. in_ready_o may be low at any time,
// but a beat waiting more than 64N cycles fails. An asynchronous reset hits
// mid-matrix, while a result drains (that result must not appear) and, as a
// short pulse between clock edges, while out_valid_o is high; out_valid_o must
// drop at once and the next matrix must come out clean.
module systolic_mm_chk #(
    parameter int N = 4,
    parameter int DW = 8,
    parameter int AW = 32,
    parameter int Matrices = 1000
) (
    output bit    finished,
    output int    errors,
    output string first
);
    localparam int Limit = 3 * N + 2;
    localparam int Stall = 64 * N;
    localparam logic signed [DW-1:0] Min = {1'b1, {(DW - 1) {1'b0}}};
    localparam logic signed [DW-1:0] Max = {1'b0, {(DW - 1) {1'b1}}};

    logic                  clk = 1'b0;
    logic                  rst_n = 1'b0;
    logic                  in_valid = 1'b0;
    logic                  in_last = 1'b0;
    logic [N*DW-1:0]       a_col = '0, b_row = '0;
    logic                  in_ready, out_valid;
    logic [N*N*AW-1:0]     c;

    systolic_mm #(.N(N), .DataW(DW), .AccW(AW)) u_dut (
        .clk_i(clk), .rst_ni(rst_n), .in_valid_i(in_valid), .in_ready_o(in_ready),
        .in_last_i(in_last), .a_col_i(a_col), .b_row_i(b_row), .out_valid_o(out_valid), .c_o(c)
    );

    always #5 clk = ~clk;

    typedef struct {
        logic [N*N*AW-1:0] c;
        int                k;
        int                last_edge;
    } result_t;

    int      cycle = 0;  // posedges seen so far
    result_t exp_q[$];
    bit      have_result = 0;
    logic [N*N*AW-1:0] held;
    int      num_out = 0, num_k1 = 0, num_big = 0, num_stall = 0, num_resets = 0;

    initial begin
        errors = 0;
        first = "";
        finished = 0;
    end

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("N=%0d DataW=%0d AccW=%0d cycle %0d: %s", N, DW, AW, cycle, msg);
        errors++;
    endtask

    // At a negedge: outputs settled after the previous posedge.
    task automatic observe();
        if ($isunknown(out_valid)) fail("out_valid_o unknown");
        if (out_valid === 1'b1) begin
            if (exp_q.size() == 0) fail("out_valid_o with no matrix pending (pulse longer than one cycle?)");
            else begin
                result_t r = exp_q.pop_front();
                if (cycle - r.last_edge > Limit)
                    fail($sformatf("out_valid_o %0d cycles after the last beat, limit %0d",
                                   cycle - r.last_edge, Limit));
                if (c !== r.c) begin
                    for (int i = 0; i < N; i++)
                        for (int j = 0; j < N; j++)
                            if (c[(i*N+j)*AW+:AW] !== r.c[(i*N+j)*AW+:AW]) begin
                                logic signed [AW-1:0] got, want;
                                got  = c[(i*N+j)*AW+:AW];
                                want = r.c[(i*N+j)*AW+:AW];
                                fail($sformatf("K=%0d: C[%0d][%0d] = %0d, expected %0d (mod 2**%0d)",
                                               r.k, i, j, got, want, AW));
                                i = N;
                                break;
                            end
                end
                num_out++;
            end
            have_result = 1;
            held = c;
        end else begin
            if (have_result && c !== held) fail("c_o changed without out_valid_o");
            if (exp_q.size() != 0 && cycle - exp_q[0].last_edge > Limit) begin
                fail($sformatf("no out_valid_o within %0d cycles of the last beat (K=%0d)", Limit,
                               exp_q[0].k));
                void'(exp_q.pop_front());
            end
        end
    endtask

    function automatic logic [DW-1:0] rand_val(int mode);
        if (mode == 1) return Min;
        if (mode == 2 || $urandom_range(3) == 0)
            case ($urandom_range(5))
                0, 1: return Min;
                2: return Max;
                3: return '1;
                4: return '0;
                default: return 1;
            endcase
        return DW'($urandom);
    endfunction

    initial begin
        longint acc[N][N];
        int     mat = 0, k = 0, kk = 1, mode = 0, phase = 0, stall = 0;
        bit     presenting = 0, fresh = 1, fire, did_mid = 0, did_drain = 0, did_out = 0, rst_mid, rst_drain, rst_out;
        logic [N*DW-1:0] a_cur, b_cur;

        #17 rst_n = 1'b1;
        while (mat < Matrices && errors == 0) begin
            // A new matrix starts when k == 0: pick K, operand mode and gap pattern.
            if (fresh) begin
                fresh = 0;
                mode = 0;
                if (mat == 0) kk = 1;
                else if (mat == 3) begin kk = 1024; mode = 1; end
                else if (mat == 7) begin kk = 1024; mode = 2; end
                else case ($urandom_range(19))
                    0, 1, 2, 3, 4, 5, 6, 7: kk = 1;
                    8, 9, 10, 11, 12, 13: kk = $urandom_range(8, 2);
                    14, 15, 16, 17, 18: kk = $urandom_range(40, 9);
                    default: kk = $urandom_range(200, 41);
                endcase
                phase = (mat / 20) % 3;
                if (mat == 3) phase = 0;
                if (kk == 1) num_k1++;
                if (kk == 1024) num_big++;
                foreach (acc[i, j]) acc[i][j] = 0;
            end
            @(negedge clk);
            observe();
            // Asynchronous resets: mid-matrix and while a result drains (held
            // over a clock edge), and a short pulse between edges while
            // out_valid_o is high.
            rst_mid = !did_mid && mat >= 40 && k >= 1;
            rst_drain = !did_drain && mat >= 80 && exp_q.size() != 0;
            rst_out = !did_out && mat >= 120 && out_valid === 1'b1;
            if (rst_mid || rst_drain || rst_out) begin
                did_mid |= rst_mid;
                did_drain |= rst_drain;
                did_out |= rst_out;
                in_valid = 1'b0;
                #1 rst_n = 1'b0;
                #1 if (out_valid !== 1'b0) fail("out_valid_o not cleared at once by the asynchronous reset");
                if (!rst_out) begin
                    @(posedge clk) cycle++;
                    @(negedge clk);
                    if (out_valid !== 1'b0) fail("out_valid_o high during reset");
                end
                #1 rst_n = 1'b1;
                exp_q.delete();
                have_result = 0;
                presenting = 0;
                stall = 0;
                k = 0;
                fresh = 1;
                num_resets++;
                @(posedge clk) cycle++;
                continue;
            end
            if (!presenting) begin
                case (phase)
                    0: presenting = 1;
                    1: presenting = $urandom_range(3) != 0;
                    default: presenting = $urandom_range(9) < 3;
                endcase
                if (presenting) begin
                    for (int i = 0; i < N; i++) begin
                        a_cur[i*DW+:DW] = rand_val(mode);
                        b_cur[i*DW+:DW] = rand_val(mode);
                    end
                end
            end
            in_valid = presenting;
            if (presenting) begin
                a_col = a_cur;
                b_row = b_cur;
                in_last = k == kk - 1;
            end else begin
                a_col = (N * DW)'({$urandom, $urandom});
                b_row = (N * DW)'({$urandom, $urandom});
                in_last = 1'($urandom);
            end
            #4 fire = in_valid && in_ready === 1'b1;
            if (presenting && in_ready === 1'bx) fail("in_ready_o unknown");
            @(posedge clk) cycle++;
            if (fire) begin
                for (int i = 0; i < N; i++)
                    for (int j = 0; j < N; j++)
                        acc[i][j] += longint'($signed(a_cur[i*DW+:DW])) * longint'($signed(b_cur[j*DW+:DW]));
                presenting = 0;
                stall = 0;
                k++;
                if (k == kk) begin
                    result_t r;
                    for (int i = 0; i < N; i++)
                        for (int j = 0; j < N; j++) r.c[(i*N+j)*AW+:AW] = AW'(acc[i][j]);
                    r.k = kk;
                    r.last_edge = cycle;
                    exp_q.push_back(r);
                    k = 0;
                    mat++;
                    fresh = 1;
                end
            end else if (presenting) begin
                num_stall++;
                if (++stall > Stall) fail($sformatf("in_ready_o low for %0d cycles with a beat waiting", Stall));
            end
        end
        repeat (Limit + 2) begin
            @(negedge clk);
            observe();
            in_valid = 1'b0;
            @(posedge clk) cycle++;
        end
        if (errors == 0) begin
            if (exp_q.size() != 0) fail("last result never came out");
            if (num_resets != 3) fail("harness: resets not applied");
            if (num_k1 < Matrices / 4 || num_big != 2 || num_out < Matrices - 50)
                fail($sformatf("harness: coverage (K=1 %0d, K=1024 %0d, results %0d)", num_k1, num_big,
                               num_out));
        end
        finished = 1;
    end
endmodule

module systolic_mm_tb;
    bit    fin2, fin4, fin8;
    int    err2, err4, err8;
    string first2, first4, first8;

    systolic_mm_chk #(.N(2), .DW(4), .AW(10)) u_n2 (.finished(fin2), .errors(err2), .first(first2));
    systolic_mm_chk #(.N(4), .DW(8), .AW(32)) u_n4 (.finished(fin4), .errors(err4), .first(first4));
    systolic_mm_chk #(.N(8), .DW(8), .AW(20)) u_n8 (.finished(fin8), .errors(err8), .first(first8));

    initial begin
        #20000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    initial begin
        wait (fin2 && fin4 && fin8);
        if (err2 + err4 + err8 == 0) $display("EQUIV PASS");
        else
            $display("EQUIV FAIL: %0d errors, first at %s", err2 + err4 + err8,
                     err2 ? first2 : err4 ? first4 : first8);
        $finish;
    end
endmodule
