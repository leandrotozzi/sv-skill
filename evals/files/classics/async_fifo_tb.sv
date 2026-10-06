// Grader harness for eval 116: checks async_fifo behaviour against the prompt.
// Two instances (Width 8 / Depth 16 and Width 12 / Depth 4), each with its own
// pair of unrelated clocks, run through four clock ratios (equal with a phase
// shift, 10:14, 10:6, 22:10). A scoreboard checks that every word comes out once,
// in order, with rdata_o right whenever rvalid_o is 1 (no overwrite, no double
// read, no read of an empty FIFO). Per ratio: random wvalid/rready traffic, a
// drain that must finish, and a capacity test (reader stopped, flags settled:
// exactly Depth words accepted, wfull_o then stays 1, rvalid_o is 1). After the
// other side goes quiet, wfull_o / rvalid_o must reflect the truth within 20
// cycles of the slower clock. Both resets are pulsed once mid-traffic; the FIFO
// must come back empty. No X on wfull_o / rvalid_o out of reset.
module async_fifo_tb_lane #(
    parameter int Width = 8,
    parameter int Depth = 16
);
    logic             wclk = 1'b0, rclk = 1'b0;
    logic             rst_n = 1'b0;
    logic             wvalid = 1'b0, rready = 1'b0;
    logic [Width-1:0] wdata = '0;
    logic             wfull, rvalid;
    logic [Width-1:0] rdata;

    async_fifo #(
        .Width(Width),
        .Depth(Depth)
    ) u_dut (
        .wclk_i(wclk), .wrst_ni(rst_n), .wvalid_i(wvalid), .wdata_i(wdata), .wfull_o(wfull),
        .rclk_i(rclk), .rrst_ni(rst_n), .rvalid_o(rvalid), .rready_i(rready), .rdata_o(rdata)
    );

    // Half periods in ns; constant delays only (Verilator rejects variable ones).
    int whalf = 5, rhalf = 5;
    task automatic half(int h);
        case (h)
            3: #3;
            5: #5;
            7: #7;
            default: #11;
        endcase
    endtask
    initial forever begin
        half(whalf);
        wclk = ~wclk;
    end
    initial begin
        #3;
        forever begin
            half(rhalf);
            rclk = ~rclk;
        end
    end

    int    errors = 0;
    string first = "";
    bit    done = 0;
    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("W%0d/D%0d t=%0t: %s", Width, Depth, $time, msg);
        errors++;
    endtask

    logic [Width-1:0] q[$];
    bit  live = 0;          // outputs are checked (out of reset)
    int  wprob = 0, rprob = 0;
    int  accepted = 0, popped = 0;
    logic wvalid_s = 0, wfull_s = 0;

    // Write side: drive and sample at negedge, commit at posedge.
    always @(negedge wclk) begin
        if (live && $isunknown(wfull)) fail("wfull_o unknown");
        wfull_s  = wfull;
        wvalid   = live && (($urandom % 100) < wprob);
        wdata    = Width'({$urandom, $urandom});
        wvalid_s = wvalid;
    end
    always @(posedge wclk) begin
        if (rst_n && live && wvalid_s && wfull_s === 1'b0) begin
            q.push_back(wdata);
            accepted++;
        end
    end

    // Read side: check, pop and drive at negedge (DUT removes at the next posedge).
    always @(negedge rclk) begin
        rready = ($urandom % 100) < rprob;
        if (live) begin
            if ($isunknown(rvalid)) fail("rvalid_o unknown");
            if (rvalid === 1'b1) begin
                if (q.size() == 0) fail("rvalid_o is 1 with no word in the FIFO");
                else if (rdata !== q[0])
                    fail($sformatf("rdata_o = %h, expected %h (%0d words in)", rdata, q[0],
                                   q.size()));
                if (rready && q.size() != 0) begin
                    void'(q.pop_front());
                    popped++;
                end
            end
        end
    end

    // 20 cycles of each clock in turn: at least 20 of the slower one.
    task automatic settle();
        repeat (20) @(posedge wclk);
        repeat (20) @(posedge rclk);
    endtask

    task automatic do_reset();
        live  = 0;
        @(negedge wclk);
        #1 rst_n = 1'b0;
        repeat (4) @(posedge wclk);
        repeat (4) @(posedge rclk);
        q.delete();
        @(negedge wclk);
        #1 rst_n = 1'b1;
        live = 1;
    endtask

    task automatic drain();
        wprob = 0;
        rprob = 100;
        settle();
        if (q.size() != 0) fail($sformatf("%0d words never came out", q.size()));
        if (rvalid !== 1'b0) fail("rvalid_o still 1 after the FIFO drained");
        if (wfull !== 1'b0) fail("wfull_o still 1 after the FIFO drained");
        q.delete();
    endtask

    int halves[4][2] = '{'{5, 5}, '{5, 7}, '{5, 3}, '{11, 5}};
    int mix[7][2] = '{'{100, 100}, '{90, 30}, '{30, 90}, '{50, 50}, '{100, 10}, '{10, 100},
                      '{70, 70}};

    initial begin
        #20;
        do_reset();
        for (int r = 0; r < 4; r++) begin
            int n0;
            whalf = halves[r][0];
            rhalf = halves[r][1];
            // Random traffic.
            for (int s = 0; s < 21; s++) begin
                wprob = mix[s % 7][0];
                rprob = mix[(s * 3 + r) % 7][1];
                repeat (400) @(posedge wclk);
                if (r == 1 && s == 10) do_reset();  // mid-traffic reset
            end
            drain();
            // Capacity with the reader stopped.
            rprob = 0;
            settle();
            n0 = accepted;
            wprob  = 100;
            repeat (Depth + 10) @(posedge wclk);
            wprob = 0;
            if (accepted - n0 != Depth)
                fail($sformatf("reader stopped: %0d words accepted, expected %0d",
                               accepted - n0, Depth));
            settle();
            if (wfull !== 1'b1) fail("wfull_o low with Depth words in and the reader stopped");
            if (rvalid !== 1'b1) fail("rvalid_o low with the FIFO full");
            // Drain with stalls.
            rprob = 40;
            settle();
            drain();
        end
        if (accepted < 8000 || popped < 8000)
            fail($sformatf("too little traffic: %0d writes, %0d reads", accepted, popped));
        done = 1;
    end
endmodule

module async_fifo_tb;
    async_fifo_tb_lane #(.Width(8), .Depth(16)) u_a ();
    async_fifo_tb_lane #(.Width(12), .Depth(4)) u_b ();

    initial begin
        #5000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    initial begin
        wait (u_a.done && u_b.done);
        if (u_a.errors + u_b.errors == 0) $display("EQUIV PASS");
        else
            $display("EQUIV FAIL: %0d errors, first at %s", u_a.errors + u_b.errors,
                     u_a.errors ? u_a.first : u_b.first);
        $finish;
    end
endmodule
