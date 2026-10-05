// Grader harness for eval 109: checks divider behaviour against the prompt.
// Every accepted start must give exactly one done_o pulse, at most Width+2
// cycles after the start edge, in the cycle busy_o falls, with the right
// quotient/remainder held stable until the next start. start_i while busy
// (with other operands) must be ignored.
module divider_tb;
    localparam int W = 16;
    localparam logic [W-1:0] Max = '1;

    logic         clk = 1'b0;
    logic         rst_n = 1'b0;
    logic         start = 1'b0;
    logic [W-1:0] dividend = '0, divisor = '0;
    logic         busy, done;
    logic [W-1:0] quot, rem;

    divider u_dut (
        .clk_i(clk), .rst_ni(rst_n), .start_i(start), .dividend_i(dividend),
        .divisor_i(divisor), .busy_o(busy), .done_o(done), .quotient_o(quot),
        .remainder_o(rem)
    );

    always #5 clk = ~clk;

    initial begin
        #2000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    int    errors = 0;
    string first = "";
    int    cycle = 0;        // posedges seen so far
    bit    pending = 0;      // a division is in flight
    bit    have_result = 0;  // quot/rem must hold held_q/held_r
    int    start_edge;
    int    num_done = 0;
    int    num_ignored = 0;
    logic [W-1:0] op_a, op_b, exp_q, exp_r, held_q, held_r;
    logic  prev_busy = 1'b0;

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("cycle %0d: %s", cycle, msg);
        errors++;
    endtask

    function automatic void expect_div(logic [W-1:0] a, logic [W-1:0] b);
        op_a = a;
        op_b = b;
        exp_q = (b == 0) ? Max : a / b;
        exp_r = (b == 0) ? a : a % b;
    endfunction

    // Corner operand pairs, run first; afterwards drawn at random now and then.
    logic [W-1:0] corner_a [] = '{16'd1234, 16'd0, Max, 16'd0, 16'd1, 16'd5, 16'd7, 16'd0,
                                  Max, Max, Max, 16'd1, 16'd100, 16'h8000, 16'h8000, 16'd9};
    logic [W-1:0] corner_b [] = '{16'd0, 16'd0, 16'd0, 16'd1, 16'd1, 16'd9, 16'd7, 16'd5,
                                  Max, 16'd1, 16'd2, Max, 16'd3, 16'h8001, 16'h7FFF, 16'd10};

    // Observe the outputs settled after the last posedge (we are at a negedge).
    task automatic observe();
        if ($isunknown({busy, done})) fail("busy_o/done_o unknown");
        if (done === 1'b1) begin
            if (!pending) fail("done_o without an accepted start (or longer than one cycle)");
            else begin
                if (cycle - start_edge > W + 2)
                    fail($sformatf("done_o %0d cycles after start, limit %0d", cycle - start_edge,
                                   W + 2));
                if (busy !== 1'b0) fail("busy_o still high with done_o");
                if (prev_busy !== 1'b1) fail("busy_o did not fall in the done_o cycle");
                if (quot !== exp_q || rem !== exp_r)
                    fail($sformatf("%0d / %0d gave q=%0d r=%0d, expected q=%0d r=%0d", op_a, op_b,
                                   quot, rem, exp_q, exp_r));
                pending = 0;
                have_result = 1;
                held_q = quot;
                held_r = rem;
                num_done++;
            end
        end else if (pending) begin
            if (busy !== 1'b1) fail("busy_o low before done_o");
            if (cycle - start_edge > W + 2) begin
                fail($sformatf("no done_o within %0d cycles of start (%0d / %0d)", W + 2, op_a,
                               op_b));
                pending = 0;
            end
        end else begin
            if (busy !== 1'b0) fail("busy_o high with no division in flight");
            if (have_result && (quot !== held_q || rem !== held_r))
                fail($sformatf("result changed while idle: q=%0d r=%0d, held q=%0d r=%0d", quot,
                               rem, held_q, held_r));
        end
        prev_busy = busy;
    endtask

    initial begin
        int corner = 0;
        bit did_reset = 0;
        #17 rst_n = 1'b1;
        for (int i = 0; i < 6000; i++) begin
            int phase;
            bit go;
            @(negedge clk);
            observe();
            phase = (i / 250) % 3;
            // phase 0: start held high (back-to-back); 1: frequent; 2: rare (long holds).
            go = (phase == 0) || (phase == 1 && $urandom % 3 == 0) || ($urandom % 25 == 0);
            start = go;
            if (busy === 1'b0 && go) begin
                if (corner < corner_a.size()) begin
                    dividend = corner_a[corner];
                    divisor  = corner_b[corner];
                    corner++;
                end else if ($urandom % 6 == 0) begin
                    automatic int k = $urandom % corner_a.size();
                    dividend = corner_a[k];
                    divisor  = corner_b[k];
                end else begin
                    // Random magnitudes so quotients of all sizes occur.
                    dividend = W'($urandom) >> ($urandom % W);
                    divisor  = W'($urandom) >> ($urandom % W);
                end
                expect_div(dividend, divisor);
                pending = 1;
                have_result = 0;
                start_edge = cycle + 1;
            end else begin
                // Ignored start (when busy) gets operands that differ from the live ones.
                dividend = ~op_a ^ W'($urandom % 4);
                divisor  = op_b + W'(1 + $urandom % 7);
                if (busy === 1'b1 && go) num_ignored++;
            end
            // Asynchronous reset once, in the middle of a division.
            if (!did_reset && i > 3000 && pending && cycle - start_edge == 5) begin
                did_reset = 1;
                start = 1'b0;
                #2 rst_n = 1'b0;
                #1 if (busy !== 1'b0 || done !== 1'b0) fail("busy_o/done_o not cleared by reset");
                #4 rst_n = 1'b1;
                pending = 0;
                have_result = 0;
                prev_busy = 1'b0;
            end
            @(posedge clk) cycle++;
        end
        repeat (W + 4) begin
            @(negedge clk);
            observe();
            start = 1'b0;
            @(posedge clk) cycle++;
        end
        if (pending) fail("last division never completed");
        if (num_done < 200 || num_ignored < 200)
            fail($sformatf("too few divisions (%0d) or ignored starts (%0d)", num_done,
                           num_ignored));
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d errors, first at %s", errors, first);
        $finish;
    end
endmodule
