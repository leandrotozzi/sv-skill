// Grader harness for eval 111: the leading-zero counter is combinational, so
// every Width = 16 input is checked exhaustively and Width = 32 at random.
module lzc_tb;
    logic [15:0] d16;
    logic [31:0] d32;
    logic [4:0]  cnt16;
    logic [5:0]  cnt32;
    logic        zero16, zero32;
    int          errors = 0;
    string       first = "";

    lzc #(.Width(16)) u_dut16 (.data_i(d16), .cnt_o(cnt16), .zero_o(zero16));
    lzc #(.Width(32)) u_dut32 (.data_i(d32), .cnt_o(cnt32), .zero_o(zero32));

    function automatic int lz(logic [31:0] v, int w);
        for (int i = w - 1; i >= 0; i--) if (v[i]) return w - 1 - i;
        return w;
    endfunction

    task automatic fail(string msg);
        if (errors == 0) first = msg;
        errors++;
    endtask

    initial begin
        for (int i = 0; i < 65536; i++) begin
            d16 = 16'(i);
            #1;
            if (cnt16 !== 5'(lz(32'(d16), 16)) || zero16 !== (d16 == 0))
                fail($sformatf("W16 data=%h cnt=%0d zero=%b", d16, cnt16, zero16));
        end
        for (int i = 0; i < 20000; i++) begin
            d32 = $urandom >> $urandom_range(31);
            if (i < 33) d32 = (i == 32) ? 32'h0 : 32'h1 << i;
            #1;
            if (cnt32 !== 6'(lz(d32, 32)) || zero32 !== (d32 == 0))
                fail($sformatf("W32 data=%h cnt=%0d zero=%b", d32, cnt32, zero32));
        end
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d mismatches, first at %s", errors, first);
        $finish;
    end
endmodule
