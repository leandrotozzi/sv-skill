// Grader harness for eval 130: the barrel shifter is combinational, so every
// data, amount and op is checked exhaustively at Width = 2 and 8, and Width =
// 32 and 64 at random plus corners (all ones, sign bit only, amounts 0 and
// Width-1). Expected values come from the SV shift operators.
module barrel_shift_tb;
    logic [63:0] data;
    logic [5:0]  amt;
    logic [1:0]  op;
    logic [1:0]  out2;
    logic [7:0]  out8;
    logic [31:0] out32;
    logic [63:0] out64;
    int          errors = 0;
    string       first = "";

    barrel_shift #(.Width(2))  u_dut2  (.data_i(data[1:0]),  .amt_i(amt[0:0]), .op_i(op), .data_o(out2));
    barrel_shift #(.Width(8))  u_dut8  (.data_i(data[7:0]),  .amt_i(amt[2:0]), .op_i(op), .data_o(out8));
    barrel_shift #(.Width(32)) u_dut32 (.data_i(data[31:0]), .amt_i(amt[4:0]), .op_i(op), .data_o(out32));
    barrel_shift #(.Width(64)) u_dut64 (.data_i(data),       .amt_i(amt),      .op_i(op), .data_o(out64));

    // Operator model on the low w bits of d, a < w.
    function automatic logic [63:0] model(logic [63:0] d, int a, logic [1:0] o, int w);
        logic [63:0] mask = (w == 64) ? '1 : (64'd1 << w) - 1;
        logic signed [63:0] sd = $signed(d << (64 - w)) >>> (64 - w);
        logic signed [63:0] sra;
        d &= mask;
        sra = sd >>> a;  // own statement: in the & below the context is unsigned
        case (o)
            2'd0:    return (d << a) & mask;
            2'd1:    return d >> a;
            2'd2:    return sra & mask;
            default: return ((d >> a) | (d << (w - a))) & mask;
        endcase
    endfunction

    task automatic fail(string msg);
        if (errors == 0) first = msg;
        errors++;
    endtask

    // Apply data/amt/op to the Width = w instance and compare after #1.
    task automatic check(int w, logic [63:0] d, int a, logic [1:0] o);
        logic [63:0] got, exp;
        data = d;
        amt  = 6'(a);
        op   = o;
        #1;
        case (w)
            2:       got = 64'(out2);
            8:       got = 64'(out8);
            32:      got = 64'(out32);
            default: got = out64;
        endcase
        exp = model(d, a, o, w);
        if (got !== exp)
            fail($sformatf("W%0d op=%0d amt=%0d data=%h got=%h exp=%h", w, o, a, d, got, exp));
    endtask

    initial begin
        for (int o = 0; o < 4; o++) begin
            for (int a = 0; a < 2; a++)
                for (int d = 0; d < 4; d++) check(2, 64'(d), a, 2'(o));
            for (int a = 0; a < 8; a++)
                for (int d = 0; d < 256; d++) check(8, 64'(d), a, 2'(o));
        end
        for (int k = 0; k < 2; k++) begin
            automatic int w = k ? 64 : 32;
            automatic logic [63:0] corners [4] = '{'1, 64'd1 << (w - 1), 64'h5555_5555_5555_5555, 64'd1};
            for (int o = 0; o < 4; o++) begin
                foreach (corners[c])
                    for (int a = 0; a < w; a++) check(w, corners[c], a, 2'(o));
                for (int i = 0; i < 5000; i++) begin
                    check(w, {$urandom, $urandom}, $urandom_range(w - 1), 2'(o));
                    check(w, {$urandom, $urandom}, i[0] ? w - 1 : 0, 2'(o));
                end
            end
        end
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d mismatches, first at %s", errors, first);
        $finish;
    end
endmodule
