// Grader harness for eval 120: self-checking AXI-Stream 32-to-8 downsizer test.
// A model scoreboard checks every output byte and m_tlast_o against the kept
// input bytes (byte 0 first). Also checked: AXI-Stream stability (m_tvalid_o,
// m_tdata_o, m_tlast_o held until m_tready_i), no X on valid outputs, one byte
// per cycle with s_tvalid_i and m_tready_i held at 1, m_tvalid_o not reacting
// to a mid-cycle toggle of s_tvalid_i, and reset emptying the converter.
module axis_downsizer_tb;
    logic        clk = 1'b0;
    logic        rst_n = 1'b0;
    logic        s_tvalid = 1'b0;
    logic        s_tready;
    logic [31:0] s_tdata = '0;
    logic [3:0]  s_tkeep = 4'b1111;
    logic        s_tlast = 1'b0;
    logic        m_tvalid;
    logic        m_tready = 1'b0;
    logic [7:0]  m_tdata;
    logic        m_tlast;

    axis_downsizer u_dut (
        .clk_i(clk), .rst_ni(rst_n), .s_tvalid_i(s_tvalid), .s_tready_o(s_tready),
        .s_tdata_i(s_tdata), .s_tkeep_i(s_tkeep), .s_tlast_i(s_tlast), .m_tvalid_o(m_tvalid),
        .m_tready_i(m_tready), .m_tdata_o(m_tdata), .m_tlast_o(m_tlast)
    );

    always #5 clk = ~clk;

    initial begin
        #5000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    int    errors = 0;
    string first = "";
    int    cycle = 0;
    logic [8:0] expq[$];        // {last, byte} still to come out
    bit    s_pending = 0;       // current input beat not yet accepted
    bit    prev_stall = 0;      // m_tvalid && !m_tready at the last edge
    logic [7:0] prev_data;
    logic  prev_last;
    int    num_bytes = 0, num_beats = 0, num_last = 0, num_stall = 0;
    int    keep_seen[4] = '{0, 0, 0, 0};

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("cycle %0d: %s", cycle, msg);
        errors++;
    endtask

    function automatic logic [3:0] rand_keep();
        case ($urandom % 4)
            0: return 4'b0001;
            1: return 4'b0011;
            2: return 4'b0111;
            default: return 4'b1111;
        endcase
    endfunction

    // One cycle: drive at negedge, check, handshake bookkeeping, posedge.
    // pv/pr: percent chance of s_tvalid / m_tready; hold: throughput window.
    task automatic step(int pv, int pr, bit check_full);
        logic mv;
        @(negedge clk);
        // Outputs settled after the last posedge.
        if ($isunknown(m_tvalid)) fail("m_tvalid_o unknown");
        if (prev_stall) begin
            if (m_tvalid !== 1'b1) fail("m_tvalid_o dropped without m_tready_i");
            else if (m_tdata !== prev_data || m_tlast !== prev_last)
                fail($sformatf("m_tdata_o/m_tlast_o changed while stalled: %h/%b -> %h/%b",
                               prev_data, prev_last, m_tdata, m_tlast));
        end
        if (check_full && m_tvalid !== 1'b1)
            fail("gap in the output with s_tvalid_i and m_tready_i held at 1");
        // New inputs.
        m_tready = ($urandom % 100) < pr;
        if (!s_pending) begin
            s_tvalid = ($urandom % 100) < pv;
            s_tdata  = $urandom;
            s_tkeep  = rand_keep();
            s_tlast  = $urandom % 3 == 0;
        end
        // m_tvalid_o must not follow a glitch on s_tvalid_i.
        #1 mv = m_tvalid;
        s_tvalid = ~s_tvalid;
        #1 if (m_tvalid !== mv) fail("m_tvalid_o depends combinationally on s_tvalid_i");
        s_tvalid = ~s_tvalid;
        #1;
        // Handshakes at the coming posedge.
        if (m_tvalid === 1'b1) begin
            if ($isunknown({m_tdata, m_tlast})) fail("m_tdata_o/m_tlast_o unknown while valid");
            if (m_tready) begin
                if (expq.size() == 0) fail($sformatf("unexpected output byte %h", m_tdata));
                else begin
                    automatic logic [8:0] e = expq.pop_front();
                    if ({m_tlast, m_tdata} !== e)
                        fail($sformatf("got byte %h last %b, expected byte %h last %b",
                                       m_tdata, m_tlast, e[7:0], e[8]));
                end
                num_bytes++;
            end else num_stall++;
        end
        prev_stall = m_tvalid === 1'b1 && !m_tready;
        prev_data = m_tdata;
        prev_last = m_tlast;
        if (s_tvalid) begin
            if ($isunknown(s_tready)) fail("s_tready_o unknown");
            if (s_tready === 1'b1) begin
                for (int k = 0; k < 4; k++)
                    if (s_tkeep[k])
                        expq.push_back({s_tlast && (k == 3 || !s_tkeep[k+1]), s_tdata[8*k +: 8]});
                keep_seen[$countones(s_tkeep) - 1]++;
                num_beats++;
                if (s_tlast) num_last++;
                s_pending = 0;
            end else s_pending = 1;
        end
        @(posedge clk) cycle++;
    endtask

    task automatic do_reset();
        s_tvalid = 1'b0;
        s_pending = 0;
        #1 rst_n = 1'b0;
        #2 if (m_tvalid !== 1'b0) fail("m_tvalid_o not cleared by reset");
        #1 rst_n = 1'b1;
        expq.delete();
        prev_stall = 0;
    endtask

    initial begin
        int pv, pr;
        bit did_reset = 0;
        #2 if (m_tvalid !== 1'b0) fail("m_tvalid_o not 0 in reset");
        #15 rst_n = 1'b1;
        for (int blk = 0; blk < 120; blk++) begin
            case (blk % 6)
                0: begin pv = 100; pr = 100; end  // throughput window
                1: begin pv = 50;  pr = 50;  end
                2: begin pv = 100; pr = 30;  end  // heavy backpressure
                3: begin pv = 20;  pr = 100; end  // starved input
                4: begin pv = 100; pr = 90;  end
                default: begin pv = $urandom % 101; pr = 1 + $urandom % 100; end
            endcase
            for (int i = 0; i < 250; i++) step(pv, pr, blk % 6 == 0 && i >= 8);
            if (blk == 61 && !did_reset) begin
                // Reset mid-stream (the stall phase leaves bytes in flight).
                @(negedge clk);
                if (expq.size() == 0) fail("reset test found the converter empty");
                did_reset = 1;
                do_reset();
                @(posedge clk) cycle++;
                if (m_tvalid !== 1'b0) fail("m_tvalid_o not 0 after reset");
            end
        end
        // Drain.
        repeat (12) step(0, 100, 0);
        if (expq.size() != 0) fail($sformatf("%0d bytes never came out", expq.size()));
        if (num_bytes < 15000 || num_stall < 2000 || num_last < 2000 || keep_seen[0] < 500 ||
            keep_seen[1] < 500 || keep_seen[2] < 500 || keep_seen[3] < 500)
            fail($sformatf("too little traffic: %0d bytes, %0d stalls, %0d last beats", num_bytes,
                           num_stall, num_last));
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d errors, first at %s", errors, first);
        $finish;
    end
endmodule
