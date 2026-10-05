// Grader harness for eval 101: the reference (renamed seq_detect_ref) and the
// design under test get the same bits; detect_o must match on every cycle.
module seq_detect_tb;
    logic  clk = 1'b0;
    logic  rst_n = 1'b0;
    logic  bit_in = 1'b0;
    logic  det_ref, det_dut;
    int    errors = 0;
    int    cycle = 0;
    string first = "";

    seq_detect_ref u_ref (.clk_i(clk), .rst_ni(rst_n), .bit_i(bit_in), .detect_o(det_ref));
    seq_detect u_dut (.clk_i(clk), .rst_ni(rst_n), .bit_i(bit_in), .detect_o(det_dut));

    always #5 clk = ~clk;

    // Compare the outputs now.
    task automatic check();
        if (det_ref !== det_dut) begin
            if (errors == 0)
                first = $sformatf("cycle %0d: detect_o ref=%b dut=%b", cycle, det_ref, det_dut);
            errors++;
        end
    endtask

    // Compare on the negedge, then drive the next bit.
    task automatic step(input logic b);
        @(negedge clk);
        cycle++;
        check();
        bit_in = b;
    endtask

    // Send the n low bits of p, most significant first.
    task automatic send(input logic [31:0] p, input int n);
        for (int i = n - 1; i >= 0; i--) step(p[i]);
    endtask

    initial begin
        #17 rst_n = 1'b1;
        send(32'b1011011, 7);  // overlapping: detects twice
        send(32'b0000, 4);
        send(32'b1011011011, 10);  // three chained overlaps
        send(32'b0000, 4);
        send(32'b10111011, 8);  // 1011 then 1011 sharing nothing
        send(32'b0000, 4);
        send(32'b1010110, 7);  // 101 0 1 1 0: one match after a false start
        send(32'b11011, 5);
        send(32'b100101101011, 12);
        send(32'b0000, 4);
        // Reset while detect_o is 1: it must clear before the next edge.
        send(32'b1011, 4);
        step(1'b0);
        #2 rst_n = 1'b0;
        #1 check();
        step(1'b1);
        #2 rst_n = 1'b1;
        send(32'b0000, 4);
        // Reset in the middle of a pattern: 101, reset, 1 must not detect.
        send(32'b101, 3);
        #2 rst_n = 1'b0;  // asynchronous, between edges
        #1 check();  // asynchronous: cleared before any clock edge
        step(1'b1);
        step(1'b1);
        #2 rst_n = 1'b1;
        send(32'b1011, 4);
        send(32'b00000, 5);
        for (int i = 0; i < 6000; i++) begin
            step(1'($urandom));
            if (i == 3000) begin
                #2 rst_n = 1'b0;
                #1 check();  // asynchronous: cleared before any clock edge
                step(1'b1);
                step(1'b0);
                #2 rst_n = 1'b1;
            end
        end
        step(1'b0);
        step(1'b0);
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d mismatching cycles, first at %s", errors, first);
        $finish;
    end
endmodule
