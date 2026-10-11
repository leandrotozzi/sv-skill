// Copyright (c) 2026 <Company>
// All rights reserved
//
// Description:
//   Self-checking testbench for skeleton.sv. Copy it to tb/<name>_tb.sv,
//   rename the module, and replace the model and the stimulus. A model beside
//   the DUT predicts every output; step() compares, then drives the next input.
//   Prints one line, PASS or FAIL with the first mismatch; FAIL exits non-zero.
//   Build and run: references/testbench-verilator.md; +seed=N picks the run.

`default_nettype none

module skeleton_tb;
    localparam int unsigned Width = 8;  // DUT parameter under test
    localparam int NumSteps = 2000;  // random cycles after the directed ones

    logic             clk_i = 1'b0;  // 100 MHz, posedge at 5, 15, ...
    logic             rst_ni = 1'b0;  // held low for the first cycles
    logic             valid_i = 1'b0;  // DUT inputs, driven at negedge
    logic [Width-1:0] data_i = '0;
    logic             valid_o;  // DUT outputs, checked at negedge
    logic [Width-1:0] data_o;

    logic             valid_m = 1'b0;  // model: expected outputs after the next posedge
    logic [Width-1:0] data_m = '0;

    int unsigned      seed = 1;  // +seed=N to reproduce a different random run
    int               cycle = 0;  // checks done so far
    int               errors = 0;  // mismatching checks
    string            first = "";  // the first mismatch, for the FAIL line

    skeleton #(.Width(Width)) dut (.*);

    always #5 clk_i = ~clk_i;

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("cycle %0d: %s", cycle, msg);
        errors++;
    endtask

    // One clock: check what the last edge produced, then drive the next inputs
    // and advance the model by the edge they will see.
    task automatic step(input logic v, input logic [Width-1:0] d);
        @(negedge clk_i);
        cycle++;
        if (valid_o !== valid_m) begin
            fail($sformatf("valid_o=%b, want %b", valid_o, valid_m));
        end else if (valid_m && data_o !== data_m) begin
            fail($sformatf("data_o=%h, want %h", data_o, data_m));
        end
        valid_i = v;
        data_i  = d;
        valid_m = v;
        if (v) data_m = d;
    endtask

    initial begin
        void'($value$plusargs("seed=%d", seed));
        void'($urandom(seed));
        repeat (2) @(negedge clk_i);
        rst_ni = 1'b1;
        // Directed: the edges first (back-to-back, a gap, a hold).
        step(1'b1, 8'h01);
        step(1'b1, 8'hff);
        step(1'b0, 8'h00);
        step(1'b1, 8'h80);
        // Random, then a reset mid-run and random again.
        repeat (NumSteps / 2) step(1'($urandom_range(1)), Width'($urandom));
        rst_ni  = 1'b0;  // asynchronous: clears the output at once
        valid_m = 1'b0;
        step(1'b0, '0);
        rst_ni = 1'b1;
        repeat (NumSteps / 2) step(1'($urandom_range(1)), Width'($urandom));
        step(1'b0, '0);  // check the last edge
        if (errors != 0) begin
            $fatal(1, "FAIL: %0d of %0d checks, seed %0d, first at %s", errors, cycle, seed, first);
        end
        $display("PASS: %0d checks, seed %0d", cycle, seed);
        $finish;
    end
endmodule

`resetall
