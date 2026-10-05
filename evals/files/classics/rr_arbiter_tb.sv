// Grader harness for eval 106: the reference (renamed rr_arbiter_ref) and the
// candidate rr_arbiter get identical directed + random requests; gnt_o must
// match on every cycle, including across an asynchronous reset.
module rr_arbiter_tb;
    localparam int N = 4;

    logic         clk = 1'b0;
    logic         rst_n = 1'b0;
    logic [N-1:0] req = '0;
    logic [N-1:0] gnt_ref, gnt_dut;
    int           errors = 0;
    int           cycle = 0;
    string        first = "";

    rr_arbiter_ref u_ref (.clk_i(clk), .rst_ni(rst_n), .req_i(req), .gnt_o(gnt_ref));
    rr_arbiter     u_dut (.clk_i(clk), .rst_ni(rst_n), .req_i(req), .gnt_o(gnt_dut));

    always #5 clk = ~clk;

    initial begin
        #200000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    // gnt_o is combinational: compare just after each input change and just
    // before the sampling edge.
    task automatic check(string where);
        if (gnt_dut !== gnt_ref || $isunknown(gnt_ref)) begin
            if (errors == 0)
                $sformat(first, "cycle %0d (%s): req=%b gnt=%b expected %b", cycle, where, req,
                         gnt_dut, gnt_ref);
            errors++;
        end
    endtask

    task automatic step(logic [N-1:0] r);
        @(negedge clk);
        cycle++;
        req = r;
        #1 check("after drive");
        #3 check("before edge");
    endtask

    initial begin
        #17 rst_n = 1'b1;
        // All requesting: grant rotates 0,1,2,3,0,...
        repeat (3 * N) step('1);
        // Single requester at every index, twice each (priority wraps past it).
        for (int i = 0; i < N; i++) repeat (2) step(N'(1) << i);
        // Single requester walking downwards, forcing the scan to wrap.
        for (int i = N - 1; i >= 0; i--) step(N'(1) << i);
        // A requester drops out while others keep requesting.
        repeat (2) step('1);
        step(4'b1101);
        step(4'b1001);
        step(4'b0001);
        step(4'b1110);
        step('0);
        step('0);
        // Priority wrap: last index granted, then lower ones.
        step(4'b1000);
        step(4'b1001);
        step(4'b0111);
        step(4'b0110);
        // Random, with dense and sparse phases.
        for (int i = 0; i < 3000; i++) begin
            if (i == 1500) begin
                // Asynchronous reset mid-run, away from the clock edges.
                @(negedge clk);
                #2 rst_n = 1'b0;
                #1 check("in reset");
                #9 rst_n = 1'b1;
            end
            if ((i / 300) % 2 == 0) step(N'($urandom));
            else step(N'($urandom) & N'($urandom));
        end
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d mismatches, first at %s", errors, first);
        $finish;
    end
endmodule
