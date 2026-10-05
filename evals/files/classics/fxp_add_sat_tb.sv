// Grader harness for eval 104: the reference (renamed fxp_add_sat_ref) and the
// design under test get the same operands; sum_o and sat_o must match on every
// cycle.
module fxp_add_sat_tb;
    logic        clk = 1'b0;
    logic        rst_n = 1'b0;
    logic [15:0] a = 16'h0000;
    logic [15:0] b = 16'h0000;
    logic [15:0] sum_ref, sum_dut;
    logic        sat_ref, sat_dut;
    int          errors = 0;
    int          cycle = 0;
    string       first = "";

    fxp_add_sat_ref u_ref (
        .clk_i(clk), .rst_ni(rst_n), .a_i(a), .b_i(b), .sum_o(sum_ref), .sat_o(sat_ref)
    );
    fxp_add_sat u_dut (
        .clk_i(clk), .rst_ni(rst_n), .a_i(a), .b_i(b), .sum_o(sum_dut), .sat_o(sat_dut)
    );

    always #5 clk = ~clk;

    // Compare the outputs now.
    task automatic check();
        if (sum_ref !== sum_dut || sat_ref !== sat_dut) begin
            if (errors == 0)
                first = $sformatf("cycle %0d (prev a=%h b=%h): sum_o ref=%h dut=%h, sat_o ref=%b dut=%b",
                                  cycle, a, b, sum_ref, sum_dut, sat_ref, sat_dut);
            errors++;
        end
    endtask

    // Compare on the negedge, then drive the next operands.
    task automatic step(input logic [15:0] x, input logic [15:0] y);
        @(negedge clk);
        cycle++;
        check();
        a = x;
        b = y;
    endtask

    // Operands near the edges of the range.
    function automatic logic [15:0] edgy();
        int unsigned r = $urandom_range(5);
        case (r)
            0: return 16'h7FFF - 16'($urandom_range(3));
            1: return 16'h8000 + 16'($urandom_range(3));
            2: return 16'($urandom_range(3));
            3: return 16'hFFFF - 16'($urandom_range(3));
            default: return 16'($urandom);
        endcase
    endfunction

    initial begin
        #17 rst_n = 1'b1;
        step(16'h7000, 16'h0FFF);  // exactly most positive: no clamp
        step(16'h7000, 16'h1000);  // one over: clamp high
        step(16'h7FFF, 16'h0000);
        step(16'h7FFF, 16'h0001);
        step(16'h7FFF, 16'h7FFF);
        step(16'h9000, 16'hF000);  // exactly most negative: no clamp
        step(16'h9000, 16'hEFFF);  // one under: clamp low
        step(16'h8000, 16'h0000);
        step(16'h8000, 16'hFFFF);
        step(16'h8000, 16'h8000);
        step(16'h7FFF, 16'h8000);  // -1, mixed signs never clamp
        step(16'h8000, 16'h7FFF);
        step(16'h4000, 16'h3FFF);
        step(16'h4000, 16'h4000);
        step(16'hC000, 16'hC000);
        step(16'hC000, 16'hBFFF);
        step(16'h0000, 16'h0000);
        step(16'hFFFF, 16'h0001);
        // Asynchronous reset between edges while an overflow is registered.
        step(16'h7FFF, 16'h7FFF);
        step(16'h7FFF, 16'h7FFF);
        #2 rst_n = 1'b0;
        #1 check();  // asynchronous: cleared before any clock edge
        step(16'h7FFF, 16'h7FFF);
        step(16'h8000, 16'h8000);
        #2 rst_n = 1'b1;
        step(16'h7FFF, 16'h7FFF);
        for (int i = 0; i < 8000; i++) begin
            if ($urandom_range(1)) step(16'($urandom), 16'($urandom));
            else step(edgy(), edgy());
        end
        step(16'h0000, 16'h0000);
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d mismatching cycles, first at %s", errors, first);
        $finish;
    end
endmodule
