// Grader harness for eval 119: checks spi_master behaviour against the prompt
// for ClkDiv 1, 2 and the default 4, all four modes, with an SPI slave model.
// Per transfer: cs_no falls only after an accepted start, with sclk_o already
// at the new cpol (before that it may move once from the old cpol to the new);
// at least ClkDiv cycles to the first edge, exactly 16 edges exactly ClkDiv
// cycles apart, at least ClkDiv cycles from the last edge to cs_no rising;
// mosi_o carries tx_data MSB first, stable in the cycles before and after each
// sampling edge (cpha 0: leading, also bit 7 from cs_no falling; cpha 1:
// trailing); rx_data_o equals the slave byte at done_o and holds it until the
// next done_o. Idle: cs_no 1, sclk_o the last cpol (0 after reset). done_o is
// one cycle, once cs_no is back at 1, in the cycle busy_o falls; busy_o is 1
// from the cycle after the start edge; start_i while busy is ignored; the
// transfer ends within 32*ClkDiv+8 cycles; an asynchronous reset mid-transfer
// returns to idle.
module spi_master_tb_unit #(
    parameter int  Div        = 4,
    parameter bit  UseDefault = 1'b0,
    parameter int  NumXfers   = 2000
);
    logic       clk = 1'b0;
    logic       rst_n = 1'b0;
    logic       start = 1'b0, cpol = 1'b0, cpha = 1'b0;
    logic [7:0] tx = '0;
    logic       busy, done, sclk, mosi, cs_n;
    logic [7:0] rx;
    logic       miso = 1'b0;

    if (UseDefault) begin : g_default
        spi_master u_dut (
            .clk_i(clk), .rst_ni(rst_n), .start_i(start), .cpol_i(cpol), .cpha_i(cpha),
            .tx_data_i(tx), .busy_o(busy), .done_o(done), .rx_data_o(rx), .sclk_o(sclk),
            .mosi_o(mosi), .miso_i(miso), .cs_no(cs_n)
        );
    end else begin : g_param
        spi_master #(.ClkDiv(Div)) u_dut (
            .clk_i(clk), .rst_ni(rst_n), .start_i(start), .cpol_i(cpol), .cpha_i(cpha),
            .tx_data_i(tx), .busy_o(busy), .done_o(done), .rx_data_o(rx), .sclk_o(sclk),
            .mosi_o(mosi), .miso_i(miso), .cs_no(cs_n)
        );
    end

    always #5 clk = ~clk;

    int    errors = 0;
    string first = "";
    bit    finished = 0;
    int    cycle = 0;       // posedges seen so far
    int    phase = 0;       // 0 idle, 1 accepted (cs_no high), 2 cs_no low, 3 cs_no back high
    int    start_edge, c0, last_edge, edges;
    bit    moved;           // sclk_o already at the new cpol (phase 1)
    bit    idle_cpol = 0;
    bit    t_cpol, t_cpha;
    logic [7:0] t_tx, s_byte, held_rx;
    bit    have_result = 0;
    logic  p_sclk = 1'b0, p_mosi = 1'b0;
    // Slave: pending miso change.
    bit    drive_pending = 0;
    int    drive_at;
    logic  drive_val;
    int    num_done = 0, num_ignored = 0;
    int    mode_count[4] = '{0, 0, 0, 0};

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("ClkDiv %0d, cycle %0d: %s", Div, cycle, msg);
        errors++;
    endtask

    task automatic slave_drive(logic v);
        int d = $urandom % Div;  // change within the half period after the edge
        if (d == 0) miso = v;
        else begin
            drive_pending = 1;
            drive_at = cycle + d;
            drive_val = v;
        end
    endtask

    // Observe the outputs settled after posedge `cycle` (we are at a negedge).
    task automatic observe();
        if ($isunknown({busy, done, sclk, cs_n})) fail("busy_o/done_o/sclk_o/cs_no unknown");
        // Slave miso: junk while deselected, pending bit changes otherwise.
        if (drive_pending && cycle == drive_at) begin
            miso = drive_val;
            drive_pending = 0;
        end
        if (phase != 2) miso = $urandom;
        if (phase == 1) begin
            if (cs_n === 1'b0) begin
                if (sclk !== t_cpol) fail("sclk_o not at the new cpol when cs_no fell");
                if (t_cpha == 0 && mosi !== t_tx[7]) fail("mosi_o not bit 7 when cs_no fell");
                c0 = cycle;
                last_edge = cycle;
                edges = 0;
                phase = 2;
                if (t_cpha == 0) slave_drive(s_byte[7]);
            end else begin
                if (sclk !== t_cpol && (moved || t_cpol == idle_cpol))
                    fail("sclk_o edge while waiting for cs_no to fall");
                if (sclk === t_cpol) moved = 1;
                if (done !== 1'b0) fail("done_o before cs_no fell");
            end
        end else if (phase == 2) begin
            if (cs_n === 1'b1) begin
                if (edges != 16) fail($sformatf("cs_no rose after %0d sclk_o edges", edges));
                else if (cycle - last_edge < Div)
                    fail($sformatf("cs_no rose %0d cycles after the last edge", cycle - last_edge));
                if (sclk !== p_sclk) fail("sclk_o changed as cs_no rose");
                phase = 3;
                drive_pending = 0;
                miso = $urandom;
            end else if (sclk !== p_sclk) begin
                bit sample = (edges % 2 == 0) == (t_cpha == 0);
                if (edges == 0 && cycle - c0 < Div)
                    fail($sformatf("first sclk_o edge %0d cycles after cs_no fell", cycle - c0));
                if (edges > 0 && cycle - last_edge != Div)
                    fail($sformatf("sclk_o half period %0d cycles", cycle - last_edge));
                if (edges >= 16) fail("more than 16 sclk_o edges");
                else if (sample) begin
                    logic b = t_tx[7-edges/2];
                    if (p_mosi !== b || mosi !== b)
                        fail($sformatf("mode %0d tx %h: mosi_o %b/%b around sampling edge %0d, expected %b",
                                       {t_cpol, t_cpha}, t_tx, p_mosi, mosi, edges, b));
                end else if (t_cpha == 1 && edges <= 14) slave_drive(s_byte[7-edges/2]);
                else if (t_cpha == 0 && edges <= 13) slave_drive(s_byte[6-edges/2]);
                edges++;
                last_edge = cycle;
            end else begin
                if (edges > 0 && edges < 16 && cycle - last_edge == Div)
                    fail($sformatf("sclk_o half period longer than %0d cycles", Div));
                if (edges == 0 && t_cpha == 0 && mosi !== t_tx[7])
                    fail("mosi_o left bit 7 before the first edge");
            end
            if (done !== 1'b0 && phase == 2) fail("done_o while cs_no low");
        end
        if (phase == 3) begin
            if (cs_n !== 1'b1) fail("cs_no fell again before done_o");
            if (sclk !== t_cpol) fail("sclk_o left cpol after cs_no rose");
        end
        if (phase == 0) begin
            if (cs_n !== 1'b1) fail("cs_no low while idle");
            if (sclk !== idle_cpol) fail($sformatf("idle sclk_o %b, expected %b", sclk, idle_cpol));
            if (busy !== 1'b0) fail("busy_o high while idle");
        end
        if (done === 1'b1) begin
            if (phase != 3) fail("done_o without a finished transfer");
            else begin
                if (busy !== 1'b0) fail("busy_o still high with done_o");
                if (rx !== s_byte)
                    fail($sformatf("mode %0d: rx_data_o %h, slave sent %h",
                                   {t_cpol, t_cpha}, rx, s_byte));
                held_rx = rx;
                have_result = 1;
                idle_cpol = t_cpol;
                phase = 0;
                num_done++;
                mode_count[{t_cpol, t_cpha}]++;
            end
        end else begin
            if (phase != 0 && cycle >= start_edge && busy !== 1'b1)
                fail("busy_o low before done_o");
            if (have_result && rx !== held_rx) fail("rx_data_o changed before done_o");
        end
        if (phase != 0 && cycle - start_edge > 32 * Div + 8) begin
            fail("transfer did not finish within 32*ClkDiv+8 cycles");
            phase = 0;
            idle_cpol = sclk;
        end
        p_sclk = sclk;
        p_mosi = mosi;
    endtask

    initial begin
        bit did_reset = 0;
        int i = 0;
        #17 rst_n = 1'b1;
        while (num_done < NumXfers && i < NumXfers * (40 * Div + 20)) begin
            int  rate;
            bit  go;
            @(negedge clk);
            observe();
            rate = (i / 400) % 3;
            // rate 0: start held high (back-to-back); 1: frequent; 2: rare.
            go = (rate == 0) || (rate == 1 && $urandom % 3 == 0) || ($urandom % 40 == 0);
            start = go;
            {cpol, cpha} = 2'($urandom);
            tx = 8'($urandom);
            if (busy === 1'b0 && phase == 0 && go) begin
                if (num_done < 8) tx = (num_done % 2) ? 8'h00 : 8'hFF;
                t_cpol = cpol;
                t_cpha = cpha;
                t_tx = tx;
                s_byte = (num_done < 8) ? ~tx : 8'($urandom);
                moved = 0;
                phase = 1;
                start_edge = cycle + 1;
            end else if (busy === 1'b1 && go) num_ignored++;
            // Asynchronous reset once, mid-transfer with sclk_o away from 0.
            if (!did_reset && num_done > NumXfers / 2 && phase == 2 && edges == 4 && t_cpol) begin
                did_reset = 1;
                start = 1'b0;
                #2 rst_n = 1'b0;
                #1 if (busy !== 1'b0 || done !== 1'b0 || cs_n !== 1'b1 || sclk !== 1'b0)
                    fail("busy_o/done_o/cs_no/sclk_o not reset");
                #4 rst_n = 1'b1;
                phase = 0;
                have_result = 0;
                idle_cpol = 0;
                drive_pending = 0;
            end
            @(posedge clk) cycle++;
            i++;
        end
        repeat (40 * Div + 20) begin
            @(negedge clk);
            observe();
            start = 1'b0;
            @(posedge clk) cycle++;
        end
        if (phase != 0) fail("last transfer never completed");
        if (num_done < NumXfers || num_ignored < 200 || !did_reset)
            fail($sformatf("too few transfers (%0d) or ignored starts (%0d), reset %0d",
                           num_done, num_ignored, did_reset));
        foreach (mode_count[m])
            if (mode_count[m] < NumXfers / 8) fail($sformatf("mode %0d ran only %0d times", m,
                                                            mode_count[m]));
        finished = 1;
    end
endmodule

module spi_master_tb;
    spi_master_tb_unit #(.Div(1)) u_div1 ();
    spi_master_tb_unit #(.Div(2)) u_div2 ();
    spi_master_tb_unit #(.Div(4), .UseDefault(1'b1)) u_div4 ();

    initial begin
        #200000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    initial begin
        int    errors;
        string first;
        wait (u_div1.finished && u_div2.finished && u_div4.finished);
        errors = u_div1.errors + u_div2.errors + u_div4.errors;
        first = u_div1.errors ? u_div1.first : u_div2.errors ? u_div2.first : u_div4.first;
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d errors, first at %s", errors, first);
        $finish;
    end
endmodule
