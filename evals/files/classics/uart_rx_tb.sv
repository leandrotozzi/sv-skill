// Grader harness for eval 110: drives 8N1 frames on rx_i at exactly ClksPerBit
// clocks per bit, edges deliberately not aligned to the clock. Checks the exact
// sequence of valid_o (with data_o) and frame_err_o pulses, each one cycle wide;
// short start glitches must produce nothing.
/* verilator lint_off ZERODLY */  // random (always non-zero) delays
module uart_rx_tb;
    localparam int Cpb = 16;          // the design's default ClksPerBit
    localparam int Period = 10;
    localparam int BitT = Cpb * Period;

    logic       clk = 1'b0;
    logic       rst_n = 1'b0;
    logic       rx = 1'b1;
    logic       valid, frame_err;
    logic [7:0] data;

    uart_rx u_dut (
        .clk_i(clk), .rst_ni(rst_n), .rx_i(rx), .valid_o(valid), .data_o(data),
        .frame_err_o(frame_err)
    );

    always #(Period / 2) clk = ~clk;

    initial begin
        #5000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    int    errors = 0;
    string first = "";
    int    exp_q[$];  // byte, or -1 for a framing error
    int    num_valid = 0, num_err = 0, exp_valid = 0, exp_err = 0, num_glitch = 0;
    logic  prev_valid = 1'b0, prev_err = 1'b0;

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("t=%0t: %s", $time, msg);
        errors++;
    endtask

    // Outputs sampled at the negedge, away from the clock edge.
    always @(negedge clk) if (rst_n) begin
        if ($isunknown({valid, frame_err})) fail("valid_o/frame_err_o unknown");
        else begin
            if (valid && frame_err) fail("valid_o and frame_err_o together");
            if ((valid && prev_valid) || (frame_err && prev_err)) fail("pulse wider than one cycle");
            if (valid && !prev_valid) begin
                num_valid++;
                if (exp_q.size() == 0) fail($sformatf("unexpected valid_o, data %h", data));
                else begin
                    automatic int e = exp_q.pop_front();
                    if (e < 0) fail($sformatf("valid_o (data %h) for a frame with stop bit 0", data));
                    else if (data !== 8'(e)) fail($sformatf("data_o %h, expected %h", data, 8'(e)));
                end
            end
            if (frame_err && !prev_err) begin
                num_err++;
                if (exp_q.size() == 0) fail("unexpected frame_err_o");
                else begin
                    automatic int e = exp_q.pop_front();
                    if (e >= 0) fail($sformatf("frame_err_o for a good frame, data %h", 8'(e)));
                end
            end
        end
        prev_valid = valid;
        prev_err = frame_err;
    end

    // Random delay of whole bits plus a fraction that never lands on a clock edge.
    task automatic gap(int min_bits, int max_bits);
        int d = BitT * (min_bits + int'($urandom % (max_bits - min_bits + 1))) +
                int'($urandom % BitT);
        while (($time + d) % (Period / 2) == 0) d++;
        #(d);
    endtask

    task automatic frame(logic [7:0] b, logic stop, bit expect_out = 1);
        if (expect_out) begin
            exp_q.push_back(stop ? int'(b) : -1);
            if (stop) exp_valid++;
            else exp_err++;
        end
        rx = 1'b0;
        #BitT;
        for (int i = 0; i < 8; i++) begin
            rx = b[i];
            #BitT;
        end
        rx = stop;
        #BitT;
        rx = 1'b1;
    endtask

    task automatic glitch();
        num_glitch++;
        rx = 1'b0;
        #((2 + $urandom % 4) * Period);  // 2..5 clocks, well under half a bit
        rx = 1'b1;
        gap(1, 2);
    endtask

    initial begin
        #23 rst_n = 1'b1;
        #(3 * BitT + 4);  // rx edges sit 2 time units off the clock edges
        // Directed: a few clean bytes, a glitch, a framing error.
        frame(8'h55, 1'b1);
        frame(8'hA3, 1'b1);
        gap(1, 2);
        glitch();
        frame(8'h00, 1'b1);
        frame(8'hFF, 1'b1);
        frame(8'h81, 1'b0);
        gap(1, 2);
        frame(8'h7E, 1'b1);
        for (int i = 0; i < 300; i++) begin
            automatic int k = $urandom % 10;
            if (i == 150) begin
                // Asynchronous reset in the middle of a frame (not counted).
                fork
                    frame(8'($urandom), 1'b1, 0);
                    begin
                        #(4 * BitT + 13) rst_n = 1'b0;
                        #3 if (valid !== 1'b0 || frame_err !== 1'b0)
                            fail("outputs not cleared by reset");
                    end
                join_any
                disable fork;
                rx = 1'b1;
                #(2 * BitT + 17) rst_n = 1'b1;
                gap(1, 2);
            end
            if (k < 2) glitch();
            else if (k < 3) begin
                // Framing error; sometimes the line stays low (a break) before idling high.
                frame(8'($urandom), 1'b0);
                if ($urandom % 2) begin
                    rx = 1'b0;
                    gap(1, 3);
                    rx = 1'b1;
                end
                gap(1, 3);
            end else begin
                frame(8'($urandom), 1'b1);
                if (k < 6) gap(0, 3);       // otherwise back-to-back
            end
        end
        #(3 * BitT);
        if (exp_q.size() != 0) fail($sformatf("%0d frames never reported", exp_q.size()));
        if (num_valid != exp_valid || num_err != exp_err)
            fail($sformatf("%0d valid_o / %0d frame_err_o pulses, expected %0d / %0d", num_valid,
                           num_err, exp_valid, exp_err));
        $display("uart_rx: %0d bytes, %0d framing errors, %0d glitches", exp_valid, exp_err,
                 num_glitch);
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d errors, first at %s", errors, first);
        $finish;
    end
endmodule
