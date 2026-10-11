// Grader harness for eval 10: the interface is fixed (TopModule, clk, reset,
// in, out; synchronous active-high reset), so the DUT is bound by those names.
// A behavioural model runs beside it; outputs compare every cycle.
module edge_detect_tb;
    logic       clk = 0;
    logic       reset;
    logic [7:0] in;
    logic [7:0] out;
    logic [7:0] prev_m, out_m;  // model: last input, expected output
    int         errors = 0;
    string      first = "";

    TopModule dut (.clk(clk), .reset(reset), .in(in), .out(out));

    always #5 clk = ~clk;

    // Model: out[i] is 1 for the cycle after in[i] was sampled rising.
    always @(posedge clk) begin
        if (reset) begin
            prev_m <= '0;
            out_m  <= '0;
        end else begin
            prev_m <= in;
            out_m  <= in & ~prev_m;
        end
    end

    initial begin
        reset = 1;
        in    = 8'hff;  // high during reset: reset cleared the history, so an edge
        repeat (3) @(negedge clk);
        reset = 0;
        for (int i = 0; i < 2000; i++) begin
            @(negedge clk);
            if (out !== out_m) begin
                if (errors == 0) first = $sformatf("cycle %0d: in=%h out=%h want %h", i, in, out, out_m);
                errors++;
            end
            in = (i % 97 == 50) ? 8'h00 : 8'($urandom);
            reset = (i % 211 == 200);  // a reset mid-run, also held for one cycle
        end
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d mismatches, first at %s", errors, first);
        $finish;
    end
endmodule
