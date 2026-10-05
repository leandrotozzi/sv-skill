// Grader harness for eval 102: the reference (renamed updown_counter_ref) and
// the design under test get the same stimulus; count_o must match on every cycle.
module updown_counter_tb;
    logic       clk = 1'b0;
    logic       rst_n = 1'b0;
    logic       en = 1'b0;
    logic       load = 1'b0;
    logic [7:0] load_val = 8'h00;
    logic       up = 1'b0;
    logic [7:0] cnt_ref, cnt_dut;
    int         errors = 0;
    int         cycle = 0;
    string      first = "";

    updown_counter_ref u_ref (
        .clk_i(clk), .rst_ni(rst_n), .en_i(en), .load_i(load), .load_val_i(load_val), .up_i(up),
        .count_o(cnt_ref)
    );
    updown_counter u_dut (
        .clk_i(clk), .rst_ni(rst_n), .en_i(en), .load_i(load), .load_val_i(load_val), .up_i(up),
        .count_o(cnt_dut)
    );

    always #5 clk = ~clk;

    // Compare the outputs now.
    task automatic check();
        if (cnt_ref !== cnt_dut) begin
            if (errors == 0)
                first = $sformatf("cycle %0d: count_o ref=%0d dut=%0d", cycle, cnt_ref, cnt_dut);
            errors++;
        end
    endtask

    // Compare on the negedge, then drive the next inputs.
    task automatic step(input logic e, input logic l, input logic [7:0] v, input logic u);
        @(negedge clk);
        cycle++;
        check();
        en = e;
        load = l;
        load_val = v;
        up = u;
    endtask

    initial begin
        #17 rst_n = 1'b1;
        repeat (3) step(1, 0, 8'hAA, 1);  // count up from reset
        repeat (5) step(1, 0, 8'hAA, 0);  // down through 0: wraps to 255
        step(0, 1, 8'hFD, 0);  // load without enable
        repeat (5) step(1, 0, 8'h00, 1);  // up through 255: wraps to 0
        step(1, 1, 8'h80, 1);  // load and enable: load wins (up)
        step(1, 1, 8'h00, 0);  // load and enable: load wins (down)
        step(1, 1, 8'hFF, 1);  // load 255 with enable up
        step(1, 0, 8'h00, 1);  // wrap
        repeat (3) step(0, 0, 8'h55, 1);  // hold
        step(1, 1, 8'h00, 0);
        step(1, 0, 8'h00, 0);  // 0 - 1 wraps
        step(0, 1, 8'h5A, 0);
        step(0, 0, 8'h00, 0);  // count is 0x5A when reset hits
        // Asynchronous reset between edges, inputs active meanwhile.
        #2 rst_n = 1'b0;
        #1 check();  // asynchronous: cleared before any clock edge
        step(1, 1, 8'h42, 1);
        step(1, 0, 8'h42, 1);
        #2 rst_n = 1'b1;
        repeat (4) step(1, 0, 8'h00, 0);
        for (int i = 0; i < 8000; i++) begin
            logic [7:0] v;
            v = ($urandom_range(3) == 0) ? 8'($urandom_range(1) ? 8'hFF : 8'h00) : 8'($urandom);
            step(1'($urandom_range(9) < 7), 1'($urandom_range(9) == 0), v, 1'($urandom));
        end
        step(0, 0, 8'h00, 0);
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d mismatching cycles, first at %s", errors, first);
        $finish;
    end
endmodule
