// Grader harness for eval 103: the reference (renamed fir_ref) and the design
// under test get the same samples; valid_o must match on every cycle and
// data_o on every cycle where valid_o is 1.
module fir_tb;
    localparam int OutWidth = 16 + 16 + 3;

    logic                clk = 1'b0;
    logic                rst_n = 1'b0;
    logic                vin = 1'b0;
    logic [15:0]         din = 16'h0000;
    logic                vout_ref, vout_dut;
    logic [OutWidth-1:0] dout_ref, dout_dut;
    int                  errors = 0;
    int                  cycle = 0;
    string               first = "";

    fir_ref u_ref (
        .clk_i(clk), .rst_ni(rst_n), .valid_i(vin), .data_i(din), .valid_o(vout_ref),
        .data_o(dout_ref)
    );
    fir u_dut (
        .clk_i(clk), .rst_ni(rst_n), .valid_i(vin), .data_i(din), .valid_o(vout_dut),
        .data_o(dout_dut)
    );

    always #5 clk = ~clk;

    // Compare the outputs now.
    task automatic check();
        if (vout_ref !== vout_dut || (vout_ref === 1'b1 && dout_ref !== dout_dut)) begin
            if (errors == 0)
                first = $sformatf("cycle %0d: valid_o ref=%b dut=%b, data_o ref=%0d dut=%0d",
                                  cycle, vout_ref, vout_dut, $signed(dout_ref),
                                  $signed(dout_dut));
            errors++;
        end
    endtask

    // Compare on the negedge, then drive the next sample.
    task automatic step(input logic v, input logic [15:0] d);
        @(negedge clk);
        cycle++;
        check();
        vin = v;
        din = d;
    endtask

    // n valid samples of value d, back to back.
    task automatic run(input logic [15:0] d, input int n);
        repeat (n) step(1'b1, d);
    endtask

    initial begin
        #17 rst_n = 1'b1;
        step(1'b0, 16'h1234);  // invalid data must be ignored
        // Impulse response, back to back.
        run(16'd1, 1);
        run(16'd0, 10);
        // Impulse response with valid_i gaps and junk data in the gaps.
        step(1'b1, 16'd100);
        for (int i = 0; i < 10; i++) begin
            step(1'b0, 16'hDEAD);
            step(1'b0, 16'h7FFF);
            step(1'b1, 16'd0);
        end
        // Step responses: most positive, then most negative input.
        run(16'h7FFF, 12);
        run(16'h8000, 12);
        // Alternating extremes, worst case magnitude for the outer/inner taps.
        for (int i = 0; i < 16; i++) run(i[0] ? 16'h7FFF : 16'h8000, 1);
        run(16'hFFFF, 10);
        // Negative impulse with gaps.
        step(1'b1, 16'h8000);
        for (int i = 0; i < 9; i++) begin
            step(1'b0, 16'h8000);
            step(1'b1, 16'd0);
        end
        // Asynchronous reset between edges: history must be cleared.
        run(16'h4000, 5);
        #2 rst_n = 1'b0;
        #1 check();  // asynchronous: cleared before any clock edge
        step(1'b1, 16'h7FFF);
        step(1'b1, 16'h7FFF);
        #2 rst_n = 1'b1;
        run(16'd1, 1);
        run(16'd0, 9);
        for (int i = 0; i < 8000; i++) begin
            logic [15:0] d;
            case ($urandom_range(3))
                0: d = $urandom_range(1) ? 16'h7FFF : 16'h8000;
                default: d = 16'($urandom);
            endcase
            step(1'($urandom_range(9) < 7), d);
        end
        step(1'b0, 16'h0000);
        step(1'b0, 16'h0000);
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d mismatching cycles, first at %s", errors, first);
        $finish;
    end
endmodule
