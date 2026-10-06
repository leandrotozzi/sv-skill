// Grader harness for eval 113: reference (renamed csr_block_ref) and the design
// under test get the same bus traffic and events; rdata_o and irq_o must match
// on every cycle.
module csr_block_tb;
    logic        clk = 1'b0;
    logic        rst_n = 1'b0;
    logic        req = 1'b0;
    logic        we = 1'b0;
    logic [3:0]  addr = '0;
    logic [31:0] wdata = '0;
    logic [7:0]  ev = '0;
    logic [31:0] rdata_ref, rdata_dut;
    logic        irq_ref, irq_dut;
    int          errors = 0;
    int          cycle = 0;
    string       first = "";

    csr_block_ref u_ref (
        .clk_i(clk), .rst_ni(rst_n), .req_i(req), .we_i(we), .addr_i(addr), .wdata_i(wdata),
        .rdata_o(rdata_ref), .event_i(ev), .irq_o(irq_ref)
    );
    csr_block u_dut (
        .clk_i(clk), .rst_ni(rst_n), .req_i(req), .we_i(we), .addr_i(addr), .wdata_i(wdata),
        .rdata_o(rdata_dut), .event_i(ev), .irq_o(irq_dut)
    );

    always #5 clk = ~clk;

    task automatic check();
        if (rdata_ref !== rdata_dut || irq_ref !== irq_dut) begin
            if (errors == 0)
                first = $sformatf("cycle %0d: rdata ref=%h dut=%h irq ref=%b dut=%b", cycle,
                                  rdata_ref, rdata_dut, irq_ref, irq_dut);
            errors++;
        end
    endtask

    task automatic step(input logic r, input logic w, input logic [3:0] a, input logic [31:0] d,
                        input logic [7:0] e);
        @(negedge clk);
        cycle++;
        check();
        req = r;
        we = w;
        addr = a;
        wdata = d;
        ev = e;
    endtask

    initial begin
        #17 rst_n = 1'b1;
        for (int a = 0; a < 16; a += 4) step(1, 0, 4'(a), '0, '0);  // reset values
        step(1, 1, 4'h0, 32'hFFFF_FFA5, '0);  // CTRL keeps bits 7:0 only
        step(1, 1, 4'hC, 32'hDEAD_BEEF, '0);
        step(1, 1, 4'h8, 32'h1234_5678, '0);  // COUNT is read-only
        step(0, 0, 4'h0, '0, 8'h81);  // events set STATUS, raise irq
        step(1, 1, 4'h4, 32'h0000_0001, 8'h01);  // clear and set together: set wins
        step(1, 1, 4'h4, 32'h0000_00FF, '0);  // clear all
        step(1, 0, 4'hD, '0, '0);  // addr_i[1:0] ignored
        for (int a = 0; a < 16; a += 4) step(1, 0, 4'(a), '0, '0);
        step(1, 1, 4'h6, 32'hFFFF_FFFF, '0);
        #2 rst_n = 1'b0;
        #1 check();
        step(1, 1, 4'hC, 32'h1, 8'hFF);
        #2 rst_n = 1'b1;
        for (int i = 0; i < 20000; i++) begin
            logic [7:0] e;
            e = ($urandom_range(3) == 0) ? 8'(1 << $urandom_range(7)) : 8'h00;
            step(1'($urandom_range(3) != 0), 1'($urandom), 4'($urandom), $urandom, e);
        end
        step(0, 0, '0, '0, '0);
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d mismatching cycles, first at %s", errors, first);
        $finish;
    end
endmodule
