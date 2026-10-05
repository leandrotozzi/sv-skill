// Grader harness for eval 108: the reference (renamed crc32_ref) and the
// candidate crc32 get identical directed + random stimulus; crc_o must match
// on every cycle. The "123456789" check vector is also checked absolutely.
module crc32_tb;
    logic        clk = 1'b0;
    logic        rst_n = 1'b0;
    logic        init = 1'b0;
    logic        valid = 1'b0;
    logic [7:0]  data = 8'h00;
    logic [31:0] crc_ref, crc_dut;
    int          errors = 0;
    int          cycle = 0;
    string       first = "";
    string       check_str = "123456789";

    crc32_ref u_ref (
        .clk_i(clk), .rst_ni(rst_n), .init_i(init), .valid_i(valid), .data_i(data),
        .crc_o(crc_ref)
    );
    crc32 u_dut (
        .clk_i(clk), .rst_ni(rst_n), .init_i(init), .valid_i(valid), .data_i(data),
        .crc_o(crc_dut)
    );

    always #5 clk = ~clk;

    initial begin
        #200000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    task automatic fail(string msg);
        if (errors == 0) first = msg;
        errors++;
    endtask

    task automatic check(string where);
        if (crc_dut !== crc_ref || $isunknown(crc_ref))
            fail($sformatf("cycle %0d (%s): crc_o=%h expected %h", cycle, where, crc_dut, crc_ref));
    endtask

    // Drive one cycle on the negedge and compare before the next edge.
    task automatic step(logic i, logic v, logic [7:0] d);
        @(negedge clk);
        cycle++;
        check("before drive");
        init = i;
        valid = v;
        data = d;
        #1 check("after drive");
    endtask

    task automatic send_string(string s);
        foreach (s[k]) step(1'b0, 1'b1, s[k]);
        step(1'b0, 1'b0, 8'h00);
    endtask

    initial begin
        #17 rst_n = 1'b1;
        // Check vector straight from reset.
        send_string(check_str);
        if (crc_dut !== 32'hCBF43926)
            fail($sformatf("CRC(\"123456789\") after reset = %h, expected cbf43926", crc_dut));
        // Same vector after init_i, with valid gaps between bytes.
        step(1'b1, 1'b0, 8'h00);
        foreach (check_str[k]) begin
            step(1'b0, 1'b1, check_str[k]);
            repeat (k % 3) step(1'b0, 1'b0, 8'($urandom));
        end
        step(1'b0, 1'b0, 8'h00);
        if (crc_dut !== 32'hCBF43926)
            fail($sformatf("CRC(\"123456789\") with gaps = %h, expected cbf43926", crc_dut));
        // init_i together with valid_i: the byte is dropped.
        step(1'b0, 1'b1, 8'hA5);
        step(1'b1, 1'b1, 8'h31);
        send_string(check_str);
        if (crc_dut !== 32'hCBF43926)
            fail($sformatf("CRC after init_i+valid_i = %h, expected cbf43926", crc_dut));
        // init_i in the middle of a message.
        send_string("12345");
        step(1'b1, 1'b0, 8'h00);
        send_string(check_str);
        // Random, including the asynchronous reset mid-run.
        for (int i = 0; i < 4000; i++) begin
            if (i == 2000) begin
                @(negedge clk);
                #2 rst_n = 1'b0;
                #1 check("in reset");
                #9 rst_n = 1'b1;
            end
            step(($urandom % 40) == 0, ($urandom % 10) < 7, 8'($urandom));
        end
        step(1'b0, 1'b0, 8'h00);
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d mismatches, first at %s", errors, first);
        $finish;
    end
endmodule
