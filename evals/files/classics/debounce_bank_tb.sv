// Grader harness for eval 112: reference (renamed debounce_bank_ref) and the
// design under test, both with NumBits = 5 and CountMax = 6, get the same
// bouncing inputs; out_o must match on every cycle.
module debounce_bank_tb;
    logic       clk = 1'b0;
    logic       rst_n = 1'b0;
    logic [4:0] in = '0;
    logic [4:0] out_ref, out_dut;
    int         errors = 0;
    int         cycle = 0;
    string      first = "";

    debounce_bank_ref #(.NumBits(5), .CountMax(6)) u_ref (
        .clk_i(clk), .rst_ni(rst_n), .in_i(in), .out_o(out_ref)
    );
    debounce_bank #(.NumBits(5), .CountMax(6)) u_dut (
        .clk_i(clk), .rst_ni(rst_n), .in_i(in), .out_o(out_dut)
    );

    always #5 clk = ~clk;

    task automatic check();
        if (out_ref !== out_dut) begin
            if (errors == 0)
                first = $sformatf("cycle %0d: out_o ref=%b dut=%b", cycle, out_ref, out_dut);
            errors++;
        end
    endtask

    task automatic step(input logic [4:0] v);
        @(negedge clk);
        cycle++;
        check();
        in = v;
    endtask

    initial begin
        #17 rst_n = 1'b1;
        repeat (3) step(5'b00000);
        repeat (5) step(5'b11111);  // one edge short: no change
        step(5'b00000);
        repeat (8) step(5'b10101);  // stable long enough
        repeat (8) step(5'b01010);
        for (int k = 0; k < 6; k++) step(5'(k));  // bounce
        // Asynchronous reset between edges.
        #2 rst_n = 1'b0;
        #1 check();
        step(5'b11111);
        #2 rst_n = 1'b1;
        for (int i = 0; i < 20000; i++) begin
            // Mostly hold, sometimes flip a few bits: runs of every length.
            logic [4:0] v;
            v = in;
            if ($urandom_range(5) == 0) v ^= 5'($urandom);
            step(v);
        end
        step(in);
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d mismatching cycles, first at %s", errors, first);
        $finish;
    end
endmodule
