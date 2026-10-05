// Grader harness for eval 105: the reference (renamed fxp_mul_ref) and the
// design under test get the same operands; prod_o and sat_o must match on
// every cycle.
module fxp_mul_tb;
    logic        clk = 1'b0;
    logic        rst_n = 1'b0;
    logic [15:0] a = 16'h0000;
    logic [15:0] b = 16'h0000;
    logic [15:0] prod_ref, prod_dut;
    logic        sat_ref, sat_dut;
    int          errors = 0;
    int          cycle = 0;
    string       first = "";

    fxp_mul_ref u_ref (
        .clk_i(clk), .rst_ni(rst_n), .a_i(a), .b_i(b), .prod_o(prod_ref), .sat_o(sat_ref)
    );
    fxp_mul u_dut (
        .clk_i(clk), .rst_ni(rst_n), .a_i(a), .b_i(b), .prod_o(prod_dut), .sat_o(sat_dut)
    );

    always #5 clk = ~clk;

    // Compare the outputs now.
    task automatic check();
        if (prod_ref !== prod_dut || sat_ref !== sat_dut) begin
            if (errors == 0)
                first = $sformatf("cycle %0d (prev a=%h b=%h): prod_o ref=%h dut=%h, sat_o ref=%b dut=%b",
                                  cycle, a, b, prod_ref, prod_dut, sat_ref, sat_dut);
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

    initial begin
        #17 rst_n = 1'b1;
        step(16'h8000, 16'h8000);  // -1 * -1 = +1: saturates to 0x7FFF
        step(16'h7FFF, 16'h7FFF);  // max * max
        step(16'h8000, 16'h7FFF);  // min * max
        step(16'h7FFF, 16'h8000);
        step(16'h8000, 16'h0001);
        step(16'h8000, 16'hFFFF);
        step(16'h0001, 16'h4000);  // tie +0.5 LSB: rounds up to 1
        step(16'hFFFF, 16'h4000);  // tie -0.5 LSB: rounds up to 0
        step(16'h0003, 16'h4000);  // tie +1.5: 2
        step(16'hFFFD, 16'h4000);  // tie -1.5: -1
        step(16'h4000, 16'hFFFD);
        step(16'hFFFB, 16'hC000);  // (-5)*(-0.5) = +2.5: 3
        step(16'h0005, 16'hC000);  // 5*(-0.5) = -2.5: -2
        step(16'h0001, 16'h3FFF);  // just below a tie
        step(16'hFFFF, 16'h4001);  // just past a negative tie
        step(16'h0000, 16'h8000);
        step(16'h4000, 16'h4000);
        step(16'hC000, 16'hC000);
        step(16'hC000, 16'h4000);
        // Asynchronous reset between edges while a saturated result is registered.
        step(16'h8000, 16'h8000);
        step(16'h8000, 16'h8000);
        #2 rst_n = 1'b0;
        #1 check();  // asynchronous: cleared before any clock edge
        step(16'h8000, 16'h8000);
        step(16'h7FFF, 16'h7FFF);
        #2 rst_n = 1'b1;
        step(16'h8000, 16'h8000);
        for (int i = 0; i < 8000; i++) begin
            case ($urandom_range(3))
                // Small times a multiple of 0x4000 / 0x2000: many exact ties.
                0: step(16'(int'($urandom_range(64)) - 32), 16'($urandom_range(7)) << 13);
                1: step($urandom_range(1) ? 16'h8000 : 16'h7FFF - 16'($urandom_range(3)),
                        16'($urandom));
                default: step(16'($urandom), 16'($urandom));
            endcase
        end
        step(16'h0000, 16'h0000);
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d mismatching cycles, first at %s", errors, first);
        $finish;
    end
endmodule
