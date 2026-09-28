// Grader harness for eval 5: the original (renamed uart_tx_ref) and the
// migrated uart_tx get the same random stimulus; every output must match
// on every cycle.
module uart_tx_equiv_tb;
    logic       clk = 1'b0;
    logic       rst_n = 1'b0;
    logic       start = 1'b0;
    logic [7:0] data = 8'h00;
    logic       tx_ref, busy_ref, tx_new, busy_new;
    int         errors = 0;

    uart_tx_ref #(.CLKS_PER_BIT(3)) u_ref (
        .clk(clk), .rst_n(rst_n), .start(start), .data(data), .tx(tx_ref), .busy(busy_ref)
    );
    uart_tx #(.ClksPerBit(3)) u_new (
        .clk_i(clk), .rst_ni(rst_n), .start_i(start), .data_i(data), .tx_o(tx_new),
        .busy_o(busy_new)
    );

    always #5 clk = ~clk;

    initial begin
        #17 rst_n = 1'b1;
        for (int i = 0; i < 4000; i++) begin
            @(negedge clk);
            start = 1'($urandom);
            data = 8'($urandom);
            if (tx_ref !== tx_new || busy_ref !== busy_new) errors++;
        end
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d mismatching cycles", errors);
        $finish;
    end
endmodule
