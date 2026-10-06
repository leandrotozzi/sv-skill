// Grader harness for eval 129: checks bin2bcd behaviour against the prompt, at
// Width = 4 and 10 (every input value) and Width = 16 and 32 (corners plus random).
// bcd_o must be 4 * Digits bits wide (2, 4, 5, 10 digits). Every accepted start
// must give exactly one done_o pulse, at most Width + 2 cycles after the start
// edge, in the cycle busy_o falls, with the BCD of bin_i (units in bcd_o[3:0])
// held stable on bcd_o until the next start. bcd_o while busy is free. start_i
// while busy (with another bin_i) must be ignored. Starts come back to back,
// frequently and rarely; an asynchronous reset hits once mid-conversion.
module bin2bcd_chk #(
    parameter int W = 16,
    parameter int D = 5,
    parameter bit Exhaustive = 0,
    parameter int Cycles = 40000  // minimum; exhaustive mode runs until every value is done
) (
    output bit    finished,
    output int    errors,
    output string first
);
    localparam logic [W-1:0] Max = '1;
    localparam int Limit = W + 2;
    localparam longint unsigned NumVals = 64'd1 << W;

    logic           clk = 1'b0;
    logic           rst_n = 1'b0;
    logic           start = 1'b0;
    logic [W-1:0]   bin = '0;
    logic           busy, done;
    logic [4*D-1:0] bcd;

    bin2bcd #(.Width(W)) u_dut (
        .clk_i(clk), .rst_ni(rst_n), .start_i(start), .bin_i(bin), .busy_o(busy),
        .done_o(done), .bcd_o(bcd)
    );

    always #5 clk = ~clk;

    int  cycle = 0;        // posedges seen so far
    bit  pending = 0;      // a conversion is in flight
    bit  have_result = 0;  // bcd must hold held_bcd
    int  start_edge;
    int  num_done = 0;
    int  num_ignored = 0;
    logic [W-1:0]   op;
    logic [4*D-1:0] exp_bcd, held_bcd;
    logic prev_busy = 1'b0;
    logic [W-1:0] corners[$];

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("W=%0d cycle %0d: %s", W, cycle, msg);
        errors++;
    endtask

    function automatic logic [4*D-1:0] to_bcd(logic [W-1:0] x);
        longint unsigned v = x;
        logic [4*D-1:0] r = '0;
        for (int d = 0; d < D; d++) begin
            r[4*d+:4] = 4'(v % 10);
            v /= 10;
        end
        return r;
    endfunction

    function automatic logic [W-1:0] rand_op();
        case ($urandom % 4)
            0: return corners[$urandom % corners.size()];
            1: return W'($urandom) >> ($urandom % W);  // small values
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
                if (bcd !== exp_bcd)
                    fail($sformatf("bin %0d gave bcd %h, expected %h", op, bcd, exp_bcd));
                pending = 0;
                have_result = 1;
                held_bcd = bcd;
                num_done++;
            end
        end else if (pending) begin
            if (busy !== 1'b1) fail("busy_o low before done_o");
            if (cycle - start_edge > Limit) begin
                fail($sformatf("no done_o within %0d cycles of start (bin %0d)", Limit, op));
                pending = 0;
            end
        end else begin
            if (busy !== 1'b0) fail("busy_o high with no conversion in flight");
            if (have_result && bcd !== held_bcd)
                fail($sformatf("bcd_o changed while idle: %h, held %h", bcd, held_bcd));
        end
        prev_busy = busy;
    endtask

    initial begin
        int corner = 0;
        longint unsigned idx = 0;       // exhaustive mode: next value
        longint unsigned idx_live = 0;  // value in flight, redone if reset kills it
        bit did_reset = 0;
        errors = 0;
        first = "";
        finished = 0;
        if ($bits(u_dut.bcd_o) != 4 * D)
            fail($sformatf("bcd_o is %0d bits, expected %0d (%0d digits)",
                           $bits(u_dut.bcd_o), 4 * D, D));
        // Corners: 0, 1, 2**W - 1 and its neighbours, 10**k - 1 and 10**k, 2**(W-1) +- 1.
        corners = '{Max, '0, W'(1), Max - W'(1), W'(9), {1'b1, {(W - 1) {1'b0}}},
                    {1'b0, {(W - 1) {1'b1}}}, Max - W'(9)};
        for (longint unsigned p = 10; p < NumVals; p *= 10) begin
            corners.push_back(W'(p - 1));
            corners.push_back(W'(p));
            if (5 * p < NumVals) corners.push_back(W'(5 * p - 1));
        end
        #17 rst_n = 1'b1;
        for (int i = 0; i < 1000000 && (i < Cycles || pending || (Exhaustive && idx < NumVals));
             i++) begin
            int phase;
            bit go;
            @(negedge clk);
            observe();
            phase = (i / 250) % 3;
            // phase 0: start held high (back-to-back); 1: frequent; 2: rare (long holds).
            go = (phase == 0) || (phase == 1 && $urandom % 3 == 0) || ($urandom % 25 == 0);
            if (i >= Cycles && !(Exhaustive && idx < NumVals)) go = 0;
            start = go;
            if (busy === 1'b0 && go) begin
                if (Exhaustive) begin
                    bin = W'(idx);
                    idx_live = idx;
                    idx++;  // wraps through W'(idx) once every value has been done
                end else if (corner < corners.size()) begin
                    bin = corners[corner];
                    corner++;
                end else bin = rand_op();
                op = bin;
                exp_bcd = to_bcd(bin);
                pending = 1;
                have_result = 0;
                start_edge = cycle + 1;
            end else begin
                // Ignored start (when busy) gets a value that differs from the live one.
                bin = op ^ W'(1 + $urandom % 7) ^ {1'b1, {(W - 1) {1'b0}}};
                if (busy === 1'b1 && go) num_ignored++;
            end
            // Asynchronous reset once, in the middle of a conversion.
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
        if (pending) fail("last conversion never completed");
        if (!did_reset) fail("harness: reset never applied");
        if (Exhaustive && idx < NumVals) fail("input values left untested");
        if (num_done < 500 || num_ignored < 500)
            fail($sformatf("too few conversions (%0d) or ignored starts (%0d)", num_done,
                           num_ignored));
        finished = 1;
    end
endmodule

module bin2bcd_tb;
    bit    fin4, fin10, fin16, fin32;
    int    err4, err10, err16, err32;
    string first4, first10, first16, first32;

    bin2bcd_chk #(.W(4), .D(2), .Exhaustive(1)) u_w4 (
        .finished(fin4), .errors(err4), .first(first4)
    );
    bin2bcd_chk #(.W(10), .D(4), .Exhaustive(1)) u_w10 (
        .finished(fin10), .errors(err10), .first(first10)
    );
    bin2bcd_chk #(.W(16), .D(5)) u_w16 (.finished(fin16), .errors(err16), .first(first16));
    bin2bcd_chk #(.W(32), .D(10)) u_w32 (.finished(fin32), .errors(err32), .first(first32));

    initial begin
        #20000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    initial begin
        wait (fin4 && fin10 && fin16 && fin32);
        if (err4 + err10 + err16 + err32 == 0) $display("EQUIV PASS");
        else
            $display("EQUIV FAIL: %0d errors, first at %s", err4 + err10 + err16 + err32,
                     err4 ? first4 : err10 ? first10 : err16 ? first16 : first32);
        $finish;
    end
endmodule
