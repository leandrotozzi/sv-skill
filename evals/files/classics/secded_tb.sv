// Grader harness for eval 122: secded_enc feeds secded_dec through an XOR
// error mask. Checks that code_o[63:0] equals data_i, that a clean codeword
// decodes to the data with no flags, that every single flipped bit (data or
// check) is corrected with only single_err_o, and that every double flip sets
// only double_err_o. All 72 single errors are tried on several hundred words,
// all 2556 bit pairs on four words, random singles and pairs on the rest.
module secded_tb;
    logic [63:0] data;
    logic [71:0] code, mask;
    logic [63:0] dec_data;
    logic        single_err, double_err;
    int          errors = 0;
    int          checks = 0;
    string       first = "";

    secded_enc u_enc (.data_i(data), .code_o(code));
    secded_dec u_dec (
        .code_i(code ^ mask), .data_o(dec_data), .single_err_o(single_err),
        .double_err_o(double_err)
    );

    initial begin
        #10000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    task automatic fail(string msg);
        if (errors == 0) first = msg;
        errors++;
    endtask

    // Apply a mask with nflip flipped bits (a, b) and check the decoder.
    task automatic try_mask(int nflip, int a, int b);
        mask = '0;
        if (nflip > 0) mask[a] = 1'b1;
        if (nflip > 1) mask[b] = 1'b1;
        #1;
        checks++;
        if ($isunknown({single_err, double_err}))
            fail($sformatf("data=%h mask=%h: flags unknown", data, mask));
        else if (nflip < 2 && (dec_data !== data || single_err !== (nflip == 1) || double_err !== 0))
            fail($sformatf("data=%h flipped %0s: data_o=%h single=%b double=%b", data,
                           nflip == 0 ? "none" : $sformatf("bit %0d", a), dec_data, single_err,
                           double_err));
        else if (nflip == 2 && (single_err !== 0 || double_err !== 1))
            fail($sformatf("data=%h flipped bits %0d,%0d: single=%b double=%b", data, a, b,
                           single_err, double_err));
    endtask

    task automatic try_word(logic [63:0] d, bit all_singles, bit all_pairs);
        int a, b;
        data = d;
        mask = '0;
        #1;
        if (code[63:0] !== d) fail($sformatf("data=%h: code_o[63:0]=%h", d, code[63:0]));
        try_mask(0, 0, 0);
        if (all_singles) for (int i = 0; i < 72; i++) try_mask(1, i, 0);
        else try_mask(1, $urandom_range(71), 0);
        if (all_pairs) begin
            for (int i = 0; i < 72; i++) for (int j = i + 1; j < 72; j++) try_mask(2, i, j);
        end else begin
            repeat (4) begin
                a = $urandom_range(71);
                b = (a + 1 + $urandom_range(70)) % 72;
                try_mask(2, a, b);
            end
        end
    endtask

    initial begin
        try_word('0, 1, 1);
        try_word('1, 1, 1);
        try_word({$urandom, $urandom}, 1, 1);
        try_word({$urandom, $urandom}, 1, 1);
        for (int i = 0; i < 64; i++) begin
            try_word(64'd1 << i, 1, 0);
            try_word(~(64'd1 << i), 1, 0);
        end
        for (int i = 0; i < 300; i++) try_word({$urandom, $urandom}, 1, 0);
        for (int i = 0; i < 5000; i++) try_word({$urandom, $urandom}, 0, 0);
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d of %0d checks, first at %s", errors, checks, first);
        $finish;
    end
endmodule
