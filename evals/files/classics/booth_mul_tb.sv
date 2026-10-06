// Grader harness for eval 125: checks booth_mul behaviour against the prompt,
// at Width = 8 (all 65536 operand pairs) and Width = 16 (corners plus random).
// Every accepted start must give exactly one done_o pulse, at most Width/2 + 2
// cycles after the start edge, in the cycle busy_o falls, with the signed
// product a_i * b_i held stable on product_o until the next start. start_i
// while busy (with other operands) must be ignored. Starts come back to back,
// frequently and rarely; an asynchronous reset hits once mid-operation.
module booth_mul_chk #(
    parameter int W = 16,
    parameter bit Exhaustive = 0,
    parameter int Cycles = 30000  // random mode only
) (
    output bit    finished,
    output int    errors,
    output string first
);
    localparam logic [W-1:0] Min = {1'b1, {(W - 1) {1'b0}}};
    localparam logic [W-1:0] Max = {1'b0, {(W - 1) {1'b1}}};
    localparam logic [W-1:0] One = W'(1);
    localparam logic [W-1:0] Neg1 = '1;
    localparam int Limit = W / 2 + 2;

    logic           clk = 1'b0;
    logic           rst_n = 1'b0;
    logic           start = 1'b0;
    logic [W-1:0]   a = '0, b = '0;
    logic           busy, done;
    logic [2*W-1:0] prod;

    booth_mul #(.Width(W)) u_dut (
        .clk_i(clk), .rst_ni(rst_n), .start_i(start), .a_i(a), .b_i(b), .busy_o(busy),
        .done_o(done), .product_o(prod)
    );

    always #5 clk = ~clk;

    int  cycle = 0;        // posedges seen so far
    bit  pending = 0;      // a multiplication is in flight
    bit  have_result = 0;  // prod must hold held_p
    int  start_edge;
    int  num_done = 0;
    int  num_ignored = 0;
    logic [W-1:0]   op_a, op_b;
    logic [2*W-1:0] exp_p, held_p;
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

    function automatic void expect_mul(logic [W-1:0] x, logic [W-1:0] y);
        op_a = x;
        op_b = y;
        exp_p = $signed({{W{x[W-1]}}, x}) * $signed({{W{y[W-1]}}, y});
    endfunction

    logic [W-1:0] corner_a [] = '{Min, Min, Max, Min, Neg1, Max, 0, Min, Neg1, One, Max, Neg1,
                                  W'(5), W'(-7), Min + One, W'(3)};
    logic [W-1:0] corner_b [] = '{Min, Neg1, Max, Max, Neg1, Neg1, Min, 0, 0, Min, Min, One,
                                  W'(-3), W'(-9), Min, W'(6)};

    function automatic logic [W-1:0] rand_op();
        case ($urandom % 4)
            0: return corner_a[$urandom % corner_a.size()];
            1: return W'($signed(W'($urandom)) >>> ($urandom % W));  // small magnitudes
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
                if (prod !== exp_p)
                    fail($sformatf("%0d * %0d gave %0d, expected %0d", $signed(op_a),
                                   $signed(op_b), $signed(prod), $signed(exp_p)));
                pending = 0;
                have_result = 1;
                held_p = prod;
                num_done++;
            end
        end else if (pending) begin
            if (busy !== 1'b1) fail("busy_o low before done_o");
            if (cycle - start_edge > Limit) begin
                fail($sformatf("no done_o within %0d cycles of start (%0d * %0d)", Limit,
                               $signed(op_a), $signed(op_b)));
                pending = 0;
            end
        end else begin
            if (busy !== 1'b0) fail("busy_o high with no multiplication in flight");
            if (have_result && prod !== held_p)
                fail($sformatf("product changed while idle: %0d, held %0d", $signed(prod),
                               $signed(held_p)));
        end
        prev_busy = busy;
    endtask

    initial begin
        int corner = 0;
        int idx = 0;       // exhaustive mode: next operand pair
        int idx_live = 0;  // pair in flight, redone if reset kills it
        bit did_reset = 0;
        #17 rst_n = 1'b1;
        // Exhaustive mode needs about 400k cycles; the cap stops a DUT that never finishes.
        for (int i = 0; Exhaustive ? (idx < (1 << 2 * W) || pending) && i < 1000000 : i < Cycles;
             i++) begin
            int phase;
            bit go;
            @(negedge clk);
            observe();
            phase = (i / 250) % 3;
            // phase 0: start held high (back-to-back); 1: frequent; 2: rare (long holds).
            go = (phase == 0) || (phase == 1 && $urandom % 3 == 0) || ($urandom % 25 == 0);
            if (Exhaustive && idx >= (1 << 2 * W)) go = 0;
            start = go;
            if (busy === 1'b0 && go) begin
                if (Exhaustive) begin
                    {a, b} = (2 * W)'(idx);
                    idx_live = idx;
                    idx++;
                end else if (corner < corner_a.size()) begin
                    a = corner_a[corner];
                    b = corner_b[corner];
                    corner++;
                end else begin
                    a = rand_op();
                    b = rand_op();
                end
                expect_mul(a, b);
                pending = 1;
                have_result = 0;
                start_edge = cycle + 1;
            end else begin
                // Ignored start (when busy) gets operands that differ from the live ones.
                a = ~op_a ^ W'($urandom % 4);
                b = op_b + W'(1 + $urandom % 7);
                if (busy === 1'b1 && go) num_ignored++;
            end
            // Asynchronous reset once, in the middle of a multiplication.
            if (!did_reset && i > 3000 && pending && cycle - start_edge == 1) begin
                did_reset = 1;
                start = 1'b0;
                #2 rst_n = 1'b0;
                #1 if (busy !== 1'b0 || done !== 1'b0) fail("busy_o/done_o not cleared by reset");
                #1 if (busy !== 1'b0 || done !== 1'b0) fail("busy_o/done_o not held low in reset");
                #3 rst_n = 1'b1;
                pending = 0;
                have_result = 0;
                prev_busy = 1'b0;
                if (Exhaustive) idx = idx_live;
            end
            @(posedge clk) cycle++;
        end
        repeat (Limit + 2) begin
            @(negedge clk);
            observe();
            start = 1'b0;
            @(posedge clk) cycle++;
        end
        if (pending) fail("last multiplication never completed");
        if (!did_reset) fail("harness: reset never applied");
        if (Exhaustive && idx < (1 << 2 * W)) fail("operand pairs left untested");
        if (num_done < 500 || num_ignored < 500)
            fail($sformatf("too few multiplications (%0d) or ignored starts (%0d)", num_done,
                           num_ignored));
        finished = 1;
    end
endmodule

module booth_mul_tb;
    bit    fin8, fin16;
    int    err8, err16;
    string first8, first16;

    booth_mul_chk #(.W(8), .Exhaustive(1)) u_w8 (.finished(fin8), .errors(err8), .first(first8));
    booth_mul_chk #(.W(16)) u_w16 (.finished(fin16), .errors(err16), .first(first16));

    initial begin
        #20000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    initial begin
        wait (fin8 && fin16);
        if (err8 + err16 == 0) $display("EQUIV PASS");
        else
            $display("EQUIV FAIL: %0d errors, first at %s", err8 + err16,
                     err8 ? first8 : first16);
        $finish;
    end
endmodule
