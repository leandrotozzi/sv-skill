// Grader harness for eval 134: two pkt_drop_fifo instances (Depth 16 and 64) get
// random AXI-Stream packets of 1 to Depth + 5 beats (some much longer), a quarter
// of them marked bad with s_tuser_i on the last beat, under random and held
// valid/ready patterns, plus an asynchronous reset mid-stream. A scoreboard holds
// the beats of every completed good packet (length <= Depth, tuser 0 on the last
// beat); it checks, every cycle:
// - m_tvalid_o is 1 only when a completed good packet waits, and then m_tdata_o /
//   m_tlast_o are its next beat: good packets come out whole, unchanged and in
//   order, a beat never shows before its packet's last beat was accepted
//   (store-and-forward), and no beat of a bad or too-long packet ever shows;
// - m_tvalid_o, m_tdata_o and m_tlast_o hold while stalled;
// - after a beat leaves, the next one shows at once if it is from the same packet,
//   or from a packet completed at least 8 cycles earlier (no bubbles);
// - s_tready_o is 1 for a beat of a packet not yet past Depth beats whenever the
//   stored plus in-progress beats are at most Depth / 2 (one beat per cycle);
// - drop_cnt_o counts the bad and too-long packets, modulo 2**16, at most 3 cycles
//   late (a too-long packet may be counted from its Depth + 1-th beat on);
//   at Depth 16 more than 65536 one-beat bad packets check the wrap;
// - progress: a pending input beat or a waiting output beat (with m_tready_i at 1)
//   is taken within 64 cycles unless the buffer waits for m_tready_i.
// Packets of exactly Depth beats must get through; a reset empties the FIFO and
// clears drop_cnt_o. s_tuser_i is 0 on beats other than the last.
module pkt_drop_fifo_chk #(
    parameter int D = 16,
    parameter int Cycles = 20000,
    parameter bit Wrap = 0
) (
    input logic clk
);
    logic        rst_n = 1'b0;
    logic        s_tvalid = 1'b0, s_tlast = 1'b0, s_tuser = 1'b0, m_tready = 1'b0;
    logic [31:0] s_tdata = '0;
    logic        s_tready, m_tvalid, m_tlast;
    logic [31:0] m_tdata;
    logic [15:0] drop_cnt;

    pkt_drop_fifo #(.Depth(D)) u_dut (
        .clk_i(clk), .rst_ni(rst_n), .s_tvalid_i(s_tvalid), .s_tready_o(s_tready),
        .s_tdata_i(s_tdata), .s_tlast_i(s_tlast), .s_tuser_i(s_tuser), .m_tvalid_o(m_tvalid),
        .m_tready_i(m_tready), .m_tdata_o(m_tdata), .m_tlast_o(m_tlast),
        .drop_cnt_o(drop_cnt)
    );

    int    errors = 0;
    string first = "";
    bit    done = 0;
    int    edges = 0;        // posedges seen
    int    reset_edge = 0;   // edge after the last reset

    // Scoreboard: beats of completed good packets, oldest first.
    logic [32:0] exp_beat[$];   // {tlast, tdata}
    int          exp_cmt[$];    // edge on which its packet's last beat was accepted
    int          exp_len[$];    // its packet's length
    // Packet being sent.
    int          len_lo = 1, len_hi = D + 5, bad_pct = 25;
    int          pkt_len = 0, pkt_idx = 0;
    bit          pkt_bad = 0;
    logic [32:0] cur[$];
    bit          s_pending = 0;
    // Drops: count since reset, and edges of the ones less than 4 edges old.
    int          drops = 0;
    int          drop_q[$];
    // Output handshake state.
    bit          prev_stall = 0;
    logic [32:0] prev_beat;
    bit          popped = 0, popped_last = 0;
    int          stuck = 0;
    // Coverage.
    int          num_good = 0, num_bad = 0, num_long = 0, num_full = 0, num_stall = 0;
    int          cov_b2b = 0, cov_in = 0, max_drops = 0;

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("Depth=%0d edge %0d: %s", D, edges, msg);
        errors++;
    endtask

    task automatic set_pkts(int lo, int hi, int bad);
        len_lo  = lo;
        len_hi  = hi;
        bad_pct = bad;
    endtask

    // AXI stall rule: what was offered and not taken must still be offered.
    task automatic check_stall();
        if (prev_stall && (m_tvalid !== 1'b1 || {m_tlast, m_tdata} !== prev_beat))
            fail($sformatf("output changed while stalled: valid %b beat %h, was %h", m_tvalid,
                           {m_tlast, m_tdata}, prev_beat));
    endtask

    // Whatever is offered must be the next beat of a completed good packet.
    task automatic check_out();
        if ($isunknown({m_tvalid, s_tready})) fail("m_tvalid_o or s_tready_o unknown");
        else if (m_tvalid) begin
            if (exp_beat.size() == 0)
                fail($sformatf("m_tvalid_o with beat %h but no completed good packet waits",
                               {m_tlast, m_tdata}));
            else if ({m_tlast, m_tdata} !== exp_beat[0])
                fail($sformatf("offered tlast/tdata %b/%h, expected %b/%h", m_tlast, m_tdata,
                               exp_beat[0][32], exp_beat[0][31:0]));
        end
    endtask

    // Outputs settled after edge `edges` (called at negedge).
    task automatic observe();
        int lo, hi;
        check_stall();
        check_out();
        if (popped && exp_beat.size() != 0 && m_tvalid !== 1'b1) begin
            if (!popped_last) fail("bubble inside a packet with m_tready_i at 1");
            else if (exp_cmt[0] <= edges - 8)
                fail("bubble between stored packets with m_tready_i at 1");
        end
        if (popped && exp_beat.size() != 0 && (!popped_last || exp_cmt[0] <= edges - 8))
            cov_b2b += popped_last;
        while (drop_q.size() != 0 && drop_q[0] <= edges - 4) void'(drop_q.pop_front());
        hi = drops + (pkt_idx > D && pkt_idx < pkt_len);  // too long, not yet ended
        lo = drops - drop_q.size();
        if ($isunknown(drop_cnt)) fail("drop_cnt_o unknown");
        else if (16'(hi - int'(drop_cnt)) > hi - lo)
            fail($sformatf("drop_cnt_o=%0d, expected %0d (mod 2**16)", drop_cnt,
                           16'(drops)));
    endtask

    task automatic new_packet();
        pkt_len = len_lo + $urandom % (len_hi - len_lo + 1);
        pkt_idx = 0;
        pkt_bad = $urandom % 100 < bad_pct;
        cur.delete();
    endtask

    // One clock, entered and left at a negedge. pv / pr: percent chance of
    // s_tvalid_i / m_tready_i.
    task automatic step(int pv, int pr);
        bit acc, pop;
        int occ;
        m_tready = $urandom % 100 < pr;
        if (!s_pending) begin
            if ($urandom % 100 < pv) begin
                if (pkt_idx >= pkt_len) new_packet();
                s_tvalid = 1'b1;
                s_tlast  = pkt_idx == pkt_len - 1;
                s_tuser  = s_tlast && pkt_bad;
            end else begin
                s_tvalid = 1'b0;
                s_tlast  = 1'($urandom);
                s_tuser  = 1'($urandom);
            end
            s_tdata = $urandom;
        end
        #1;
        check_stall();
        check_out();
        occ = exp_beat.size() + pkt_idx;
        if (s_tvalid && pkt_idx < D && occ <= D / 2 && edges >= reset_edge + 3) begin
            cov_in++;
            if (s_tready !== 1'b1)
                fail($sformatf("s_tready_o low with %0d beats held of %0d", occ, D));
        end
        acc = s_tvalid && s_tready === 1'b1;
        pop = m_tvalid === 1'b1 && m_tready;
        prev_stall = m_tvalid === 1'b1 && !m_tready;
        prev_beat  = {m_tlast, m_tdata};
        num_stall += prev_stall;
        if (acc || pop) stuck = 0;
        else if ((s_tvalid && !(exp_beat.size() != 0 && !m_tready)) ||
                 (exp_beat.size() != 0 && m_tready))
            stuck++;
        if (stuck > 64) fail("no progress for 64 cycles (deadlock)");
        @(posedge clk);
        edges++;
        popped = pop && exp_beat.size() != 0;
        popped_last = 0;
        if (popped) begin
            popped_last = exp_beat[0][32];
            if (popped_last && exp_len[0] == D) num_full++;
            void'(exp_beat.pop_front());
            void'(exp_cmt.pop_front());
            void'(exp_len.pop_front());
        end
        if (acc) begin
            cur.push_back({s_tlast, s_tdata});
            pkt_idx++;
            if (s_tlast) begin
                if (pkt_len > D || pkt_bad) begin
                    drops++;
                    drop_q.push_back(edges);
                    if (drops > max_drops) max_drops = drops;
                    if (pkt_len > D) num_long++;
                    else num_bad++;
                end else begin
                    foreach (cur[i]) begin
                        exp_beat.push_back(cur[i]);
                        exp_cmt.push_back(edges);
                        exp_len.push_back(pkt_len);
                    end
                    num_good++;
                end
                cur.delete();
            end
        end
        s_pending = s_tvalid && !acc;
        @(negedge clk);
        observe();
    endtask

    task automatic do_reset();
        s_tvalid = 1'b0;
        #1 rst_n = 1'b0;
        #1 if (m_tvalid !== 1'b0 || drop_cnt !== '0)
            fail("reset did not empty the FIFO and clear drop_cnt_o");
        #1 rst_n = 1'b1;
        exp_beat.delete();
        exp_cmt.delete();
        exp_len.delete();
        cur.delete();
        pkt_idx = pkt_len;  // next beat starts a new packet
        drops = 0;
        drop_q.delete();
        s_pending = 0;
        prev_stall = 0;
        popped = 0;
        stuck = 0;
        reset_edge = edges + 1;
    endtask

    initial begin
        int pv, pr;
        @(negedge clk);
        do_reset();
        @(negedge clk);
        // Exactly Depth beats into an empty FIFO, then just too long, then much too long.
        set_pkts(D, D, 0);
        repeat (3 * D + 20) step(100, 100);
        repeat (D + 10) step(0, 100);
        set_pkts(D + 1, D + 1, 0);
        repeat (2 * D + 10) step(100, 100);
        set_pkts(3 * D, 3 * D, 0);
        repeat (6 * D + 10) step(100, 50);
        set_pkts(D, D, 0);
        repeat (2 * D) step(100, 30);
        repeat (2 * D + 10) step(0, 100);
        // Fill with output stalled, then drain with m_tready_i held at 1.
        for (int k = 0; k < 20; k++) begin
            set_pkts(1, k < 10 ? D / 4 : D / 2, 25);
            repeat (3 * D) step(100, 0);
            repeat (2 * D + 10) step(k % 2 ? 100 : 0, 100);
        end
        // Streaming: short packets, both sides held at 1.
        set_pkts(1, D / 4, 20);
        repeat (3000) step(100, 100);
        // Random traffic, with a reset mid-stream.
        set_pkts(1, D + 5, 25);
        for (int i = 0; i < Cycles; i++) begin
            if (i % 300 == 0) begin
                case ($urandom % 6)
                    0: begin pv = 90; pr = 30; end
                    1: begin pv = 30; pr = 90; end
                    2: begin pv = 70; pr = 70; end
                    3: begin pv = 100; pr = 100; end
                    4: begin pv = 100; pr = 90; end
                    default: begin pv = 20; pr = 20; end
                endcase
                if ($urandom % 8 == 0) set_pkts(D + 1, 3 * D, 25);
                else set_pkts(1, D + 5, 25);
            end
            if (i == Cycles / 2) begin
                set_pkts(1, D / 2, 0);
                repeat (3 * D) step(100, 0);
                @(negedge clk);
                if (exp_beat.size() == 0) fail("reset test found the FIFO empty");
                do_reset();
                @(negedge clk);
            end
            step(pv, pr);
        end
        // Wrap drop_cnt_o with one-beat bad packets.
        if (Wrap) begin
            set_pkts(1, 1, 100);
            repeat (65536 + 100) step(100, 100);
            set_pkts(1, D + 5, 25);
            repeat (2000) step(70, 70);
        end
        // Drain.
        repeat (2 * D + 20) step(0, 100);
        if (exp_beat.size() != 0) fail($sformatf("%0d beats never came out", exp_beat.size()));
        if (errors == 0 && (num_good < 500 || num_bad < 200 || num_long < 50 || num_full < 4 ||
                            num_stall < 1000 || cov_b2b < 100 || cov_in < 5000 ||
                            (Wrap && max_drops <= 65536)))
            fail($sformatf({"harness coverage hole: good %0d bad %0d long %0d full %0d ",
                            "stall %0d b2b %0d in %0d drops %0d"}, num_good, num_bad,
                           num_long, num_full, num_stall, cov_b2b, cov_in, max_drops));
        done = 1;
    end
endmodule

module pkt_drop_fifo_tb;
    logic clk = 1'b0;
    always #5 clk = ~clk;

    pkt_drop_fifo_chk #(.D(16), .Cycles(100000), .Wrap(1)) u_d16 (.clk(clk));
    pkt_drop_fifo_chk #(.D(64), .Cycles(200000), .Wrap(0)) u_d64 (.clk(clk));

    initial begin
        #20000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    // Stop at the first failure (a deadlocked design would otherwise run on).
    initial begin
        wait ((u_d16.done && u_d64.done) || u_d16.errors != 0 || u_d64.errors != 0);
        #1;
        if (u_d16.errors + u_d64.errors != 0)
            $display("EQUIV FAIL: %0d errors, first at %s", u_d16.errors + u_d64.errors,
                     u_d16.errors ? u_d16.first : u_d64.first);
        else $display("EQUIV PASS");
        $finish;
    end
endmodule
