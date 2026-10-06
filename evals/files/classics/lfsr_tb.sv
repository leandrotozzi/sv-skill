// Grader harness for eval 115: reference (renamed lfsr_ref) and the design
// under test, at Order = 7 and Order = 31, get the same enable/load/seed
// stimulus; state_o and bit_o must match on every cycle. The Order = 7
// sequence must also repeat with period 127.
module lfsr_tb;
    logic        clk = 1'b0;
    logic        rst_n = 1'b0;
    logic        en = 1'b0;
    logic        load = 1'b0;
    logic [30:0] seed = '0;
    logic [6:0]  s7_ref, s7_dut;
    logic [30:0] s31_ref, s31_dut;
    logic        b7_ref, b7_dut, b31_ref, b31_dut;
    int          errors = 0;
    int          cycle = 0;
    string       first = "";

    lfsr_ref #(.Order(7)) u_ref7 (
        .clk_i(clk), .rst_ni(rst_n), .en_i(en), .load_i(load), .seed_i(seed[6:0]),
        .state_o(s7_ref), .bit_o(b7_ref)
    );
    lfsr #(.Order(7)) u_dut7 (
        .clk_i(clk), .rst_ni(rst_n), .en_i(en), .load_i(load), .seed_i(seed[6:0]),
        .state_o(s7_dut), .bit_o(b7_dut)
    );
    lfsr_ref #(.Order(31)) u_ref31 (
        .clk_i(clk), .rst_ni(rst_n), .en_i(en), .load_i(load), .seed_i(seed),
        .state_o(s31_ref), .bit_o(b31_ref)
    );
    lfsr #(.Order(31)) u_dut31 (
        .clk_i(clk), .rst_ni(rst_n), .en_i(en), .load_i(load), .seed_i(seed),
        .state_o(s31_dut), .bit_o(b31_dut)
    );

    always #5 clk = ~clk;

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("cycle %0d: %s", cycle, msg);
        errors++;
    endtask

    task automatic step(input logic e, input logic l, input logic [30:0] s);
        @(negedge clk);
        cycle++;
        if (s7_ref !== s7_dut || b7_ref !== b7_dut)
            fail($sformatf("Order 7 state ref=%h dut=%h bit ref=%b dut=%b", s7_ref, s7_dut, b7_ref,
                           b7_dut));
        if (s31_ref !== s31_dut || b31_ref !== b31_dut)
            fail($sformatf("Order 31 state ref=%h dut=%h bit ref=%b dut=%b", s31_ref, s31_dut,
                           b31_ref, b31_dut));
        en = e;
        load = l;
        seed = s;
    endtask

    initial begin
        logic [6:0] start;
        #17 rst_n = 1'b1;
        step(0, 0, '0);
        start = s7_ref;
        repeat (127) step(1, 0, '0);
        step(0, 0, '0);  // observe after the 127th shift
        if (s7_ref !== start) fail("reference Order 7 period is not 127");
        step(1, 1, 31'h1234_5678);  // load wins over enable
        repeat (3) step(0, 0, '0);  // hold
        #2 rst_n = 1'b0;
        step(1, 0, '0);
        #2 rst_n = 1'b1;
        for (int i = 0; i < 20000; i++)
            step(1'($urandom_range(9) < 8), 1'($urandom_range(49) == 0), 31'($urandom));
        step(0, 0, '0);
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d mismatching cycles, first at %s", errors, first);
        $finish;
    end
endmodule
