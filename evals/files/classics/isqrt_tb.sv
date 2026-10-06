// Grader harness for eval 126: checks isqrt behaviour against the prompt, at
// Width = 8 (every radicand, then random), 16 and 32 (corners plus random).
// Every accepted start must give exactly one done_o pulse, at most Width/2 + 2
// cycles after the start edge, in the cycle busy_o falls, with root_o =
// floor(sqrt(x_i)) and rem_o = x_i - root_o^2 held stable until the next
// start. start_i while busy (with another x_i) must be ignored. Outputs while
// busy are not checked. Starts come back to back, frequently and rarely; an
// asynchronous reset hits once mid-operation.
module isqrt_chk #(
    parameter int W = 16,
    parameter bit Exhaustive = 0,
    parameter int Cycles = 30000
) (
    output bit    finished,
    output int    errors,
    output string first
);
    localparam int H = W / 2;
    localparam int Limit = H + 2;
    localparam logic [W-1:0] Ones = '1;
    localparam logic [W-1:0] Top = {1'b1, {(W - 1) {1'b0}}};
    localparam logic [H-1:0] RMax = '1;

    logic         clk = 1'b0;
    logic         rst_n = 1'b0;
    logic         start = 1'b0;
    logic [W-1:0] x = '0;
    logic         busy, done;
    logic [H-1:0] root;
    logic [H:0]   rem;

    isqrt #(.Width(W)) u_dut (
        .clk_i(clk), .rst_ni(rst_n), .start_i(start), .x_i(x), .busy_o(busy), .done_o(done),
        .root_o(root), .rem_o(rem)
    );

    always #5 clk = ~clk;

    int  cycle = 0;        // posedges seen so far
    bit  pending = 0;      // a square root is in flight
    bit  have_result = 0;  // root/rem must hold held_r/held_m
    int  start_edge;
    int  num_done = 0;
    int  num_ignored = 0;
    logic [W-1:0] op_x;
    logic [H-1:0] exp_r, held_r;
    logic [H:0]   exp_m, held_m;
    logic prev_busy = 1'b0;

    initial begin
        errors = 0;
        first = "";
        finished = 0;
    end

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("W=%0d cycle %0d: %s", W, cycle, msg);
        errors++;
    endtask

    function automatic void expect_sqrt(logic [W-1:0] v);
        longint unsigned r = 0;
        for (int b = H - 1; b >= 0; b--)
            if ((r + (64'd1 << b)) * (r + (64'd1 << b)) <= 64'(v)) r += 64'd1 << b;
        op_x = v;
        exp_r = H'(r);
        exp_m = (H + 1)'(64'(v) - r * r);
    endfunction

    // x near k^2 for a k in [0, 2^H): k^2 - 1, k^2, k^2 + 1, k^2 + 2k (largest remainder).
    function automatic logic [W-1:0] near_square(logic [H-1:0] k);
        longint unsigned s = 64'(k) * 64'(k);
        case ($urandom % 4)
            0: return W'(s - 1);
            1: return W'(s);
            2: return W'(s + 1);
            default: return W'(s + 2 * 64'(k));
        endcase
    endfunction

    logic [W-1:0] corners [] = '{0, 1, 2, 3, 4, 5, 8, 9, Ones, Ones - 1, Top, Top - 1, Top >> 1,
                                 W'(64'(RMax) * 64'(RMax)), W'(64'(RMax) * 64'(RMax) - 1),
                                 W'((64'(RMax) - 1) * (64'(RMax) + 1)), Ones >> 1, Ones >> 2};

    function automatic logic [W-1:0] rand_x();
        case ($urandom % 4)
            0: return corners[$urandom % corners.size()];
            1: return near_square(H'($urandom));
            2: return W'($urandom) >> ($urandom % W);  // small values
            default: return W'($urandom);
        endcase
    endfunction

    task automatic observe();
        if ($isunknown({busy, done})) fail("busy_o/done_o unknown");
        if (done === 1'b1) begin
            if (!pending) fail("done_o without an accepted start (or longer than one cycle)");
            else begin
                if (cycle - start_edge > Limit)
                    fail($sformatf("done_o %0d cycles after start, limit %0d",
                                   cycle - start_edge, Limit));
                if (busy !== 1'b0) fail("busy_o still high with done_o");
                if (prev_busy !== 1'b1) fail("busy_o did not fall in the done_o cycle");
                if (root !== exp_r || rem !== exp_m)
                    fail($sformatf("isqrt(%0d) gave root %0d rem %0d, expected %0d rem %0d", op_x,
                                   root, rem, exp_r, exp_m));
                pending = 0;
                have_result = 1;
                held_r = root;
                held_m = rem;
                num_done++;
            end
        end else if (pending) begin
            if (busy !== 1'b1) fail("busy_o low before done_o");
            if (cycle - start_edge > Limit) begin
                fail($sformatf("no done_o within %0d cycles of start (x = %0d)", Limit, op_x));
                pending = 0;
            end
        end else begin
            if (busy !== 1'b0) fail("busy_o high with no square root in flight");
            if (have_result && (root !== held_r || rem !== held_m))
                fail($sformatf("result changed while idle: root %0d rem %0d, held %0d rem %0d",
                               root, rem, held_r, held_m));
        end
        prev_busy = busy;
    endtask

    initial begin
        int corner = 0;
        longint idx = Exhaustive ? 0 : 64'd1 << W;  // next radicand of the exhaustive sweep
        longint idx_live = 0;  // radicand in flight, redone if reset kills it
        bit did_reset = 0;
        #17 rst_n = 1'b1;
        for (int i = 0; i < Cycles; i++) begin
            int phase;
            bit go;
            @(negedge clk);
            observe();
            phase = (i / 250) % 3;
            // phase 0: start held high (back-to-back); 1: frequent; 2: rare (long holds).
            go = (phase == 0) || (phase == 1 && $urandom % 3 == 0) || ($urandom % 25 == 0);
            start = go;
            if (busy === 1'b0 && go) begin
                if (idx < (64'd1 << W)) begin
                    x = W'(idx);
                    idx_live = idx;
                    idx++;
                end else if (corner < corners.size()) begin
                    x = corners[corner];
                    corner++;
                end else x = rand_x();
                expect_sqrt(x);
                pending = 1;
                have_result = 0;
                start_edge = cycle + 1;
            end else begin
                // Ignored start (when busy) gets a radicand with a different root.
                x = op_x ^ Top ^ W'($urandom % 16);
                if (busy === 1'b1 && go) num_ignored++;
            end
            // Asynchronous reset once, in the middle of a square root.
            if (!did_reset && i > 3000 && pending && cycle >= start_edge) begin
                did_reset = 1;
                start = 1'b0;
                #2 rst_n = 1'b0;
                #1 if (busy !== 1'b0 || done !== 1'b0) fail("busy_o/done_o not cleared by reset");
                #1 if (busy !== 1'b0 || done !== 1'b0) fail("busy_o/done_o not held low in reset");
                #3 rst_n = 1'b1;
                pending = 0;
                have_result = 0;
                prev_busy = 1'b0;
                if (Exhaustive && idx < (64'd1 << W)) idx = idx_live;
            end
            @(posedge clk) cycle++;
        end
        repeat (Limit + 2) begin
            @(negedge clk);
            observe();
            start = 1'b0;
            @(posedge clk) cycle++;
        end
        if (pending) fail("last square root never completed");
        if (!did_reset) fail("harness: reset never applied");
        if (idx < (64'd1 << W)) fail("harness: radicands left untested");
        if (num_done < 500 || num_ignored < 500)
            fail($sformatf("too few square roots (%0d) or ignored starts (%0d)", num_done,
                           num_ignored));
        finished = 1;
    end
endmodule

module isqrt_tb;
    bit    fin8, fin16, fin32;
    int    err8, err16, err32;
    string first8, first16, first32;

    isqrt_chk #(.W(8), .Exhaustive(1), .Cycles(20000)) u_w8 (
        .finished(fin8), .errors(err8), .first(first8)
    );
    isqrt_chk #(.W(16)) u_w16 (.finished(fin16), .errors(err16), .first(first16));
    isqrt_chk #(.W(32)) u_w32 (.finished(fin32), .errors(err32), .first(first32));

    initial begin
        #5000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    initial begin
        wait (fin8 && fin16 && fin32);
        if (err8 + err16 + err32 == 0) $display("EQUIV PASS");
        else
            $display("EQUIV FAIL: %0d errors, first at %s", err8 + err16 + err32,
                     err8 ? first8 : err16 ? first16 : first32);
        $finish;
    end
endmodule
