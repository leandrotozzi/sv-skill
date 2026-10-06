// Grader harness for eval 121: checks pkt_arbiter behaviour against the prompt,
// at NumIn 4 / DataWidth 16 and NumIn 3 / DataWidth 8. AXI-Stream masters (which
// hold valid/data/last until accepted) feed random packets with gaps; the slave
// side applies random backpressure. Checked: every input's beats come out
// complete and in order, never interleaved within a packet, with the right
// m_tid_o; at most one s_tready_o high and no beat accepted from another input
// while a packet is open on the input side; the output holds valid and payload
// while stalled; an input waiting with a first beat is passed over by at most
// NumIn-1 packets of other inputs; with all inputs always valid packets rotate
// strictly; with all inputs valid and m_tready_i high, beats leave every cycle
// within a packet and at most one idle cycle separates packets; m_tvalid_o is 0
// in reset (asserted once mid-packet); no stall while a beat could move.
module pkt_arbiter_tb_bench #(
    parameter int N      = 4,
    parameter int W      = 16,
    parameter int Cycles = 40000
);
    localparam int IdW = $clog2(N);

    logic           clk = 1'b0;
    logic           rst_n = 1'b0;
    logic [N-1:0]   s_tvalid = '0, s_tlast = '0;
    logic [N-1:0]   s_tready;
    logic [N*W-1:0] s_tdata = '0;
    logic           m_tvalid, m_tlast;
    logic           m_tready = 1'b0;
    logic [W-1:0]   m_tdata;
    logic [IdW-1:0] m_tid;

    pkt_arbiter #(.NumIn(N), .DataWidth(W)) u_dut (
        .clk_i(clk), .rst_ni(rst_n), .s_tvalid_i(s_tvalid), .s_tready_o(s_tready),
        .s_tdata_i(s_tdata), .s_tlast_i(s_tlast), .m_tvalid_o(m_tvalid), .m_tready_i(m_tready),
        .m_tdata_o(m_tdata), .m_tlast_o(m_tlast), .m_tid_o(m_tid)
    );

    always #5 clk = ~clk;

    int    errors = 0;
    string first = "";
    bit    done = 0;
    int    cycle = 0;

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("N=%0d cycle %0d: %s", N, cycle, msg);
        errors++;
    endtask

    // Masters.
    int           rem[N];      // beats left in the current packet, head included
    bit           sfirst[N];   // the offered beat is the first of its packet
    bit           acc[N];      // the offered beat was accepted at the last edge
    int           pv[N];       // percent chance to offer a beat when idle
    int           pr;          // percent chance of m_tready_i
    bit           allvalid, fullrate, stop;
    // Model.
    logic [W-1:0] qd[N][$];
    bit           ql[N][$];
    int           wait_cnt[N];
    bit           in_open, out_open;
    int           in_cur, out_cur;
    bit           prev_v, prev_r, prev_l;
    logic [W-1:0] prev_d;
    logic [IdW-1:0] prev_id;
    int           ph_pkts, prev_tid, last_hs, idle;
    bit           last_hs_ok;
    int           npkts = 0, nbeats = 0, nstall = 0;

    task automatic clear_model();
        for (int i = 0; i < N; i++) begin
            rem[i] = 0;
            acc[i] = 0;
            wait_cnt[i] = 0;
            qd[i].delete();
            ql[i].delete();
        end
        in_open = 0;
        out_open = 0;
        prev_v = 0;
        ph_pkts = 0;
        last_hs_ok = 0;
        idle = 0;
    endtask

    task automatic drive();
        for (int i = 0; i < N; i++) begin
            if (s_tvalid[i] && !acc[i]) continue;  // AXIS: hold until accepted
            s_tvalid[i] = 1'b0;
            acc[i] = 0;
            if (rem[i] == 0 && stop) continue;
            if (!(allvalid || stop || $urandom % 100 < pv[i])) continue;
            sfirst[i] = (rem[i] == 0);
            if (rem[i] == 0) rem[i] = ($urandom % 8 == 0) ? 8 + $urandom % 13 : 1 + $urandom % 4;
            s_tvalid[i] = 1'b1;
            s_tdata[i*W+:W] = W'($urandom);
            s_tlast[i] = (rem[i] == 1);
        end
        m_tready = fullrate || stop || ($urandom % 100 < pr);
    endtask

    task automatic sample();
        logic [N-1:0] hs;
        bit expect_move;
        if ($isunknown({m_tvalid, s_tready})) fail("m_tvalid_o/s_tready_o unknown");
        if (prev_v && !prev_r && (m_tvalid !== 1'b1 || m_tdata !== prev_d || m_tlast !== prev_l ||
                                  m_tid !== prev_id))
            fail("output changed while m_tvalid_o was high and m_tready_i low");
        if ($countones(s_tready) > 1) fail($sformatf("s_tready_o=%b has more than one bit", s_tready));
        hs = s_tvalid & s_tready;
        for (int i = 0; i < N; i++) begin
            if (!hs[i]) continue;
            if (in_open && in_cur != i)
                fail($sformatf("beat accepted from input %0d inside a packet of input %0d", i,
                               in_cur));
            qd[i].push_back(s_tdata[i*W+:W]);
            ql[i].push_back(s_tlast[i]);
            if (sfirst[i]) begin
                for (int j = 0; j < N; j++)
                    if (j != i && s_tvalid[j] && sfirst[j] && ++wait_cnt[j] > N - 1)
                        fail($sformatf("input %0d passed over by %0d packets while waiting", j,
                                       wait_cnt[j]));
                wait_cnt[i] = 0;
            end
            in_open = !s_tlast[i];
            in_cur  = i;
            rem[i]--;
            acc[i] = 1;
        end
        if (m_tvalid === 1'b1 && m_tready) begin
            if (int'(m_tid) >= N) fail($sformatf("m_tid_o=%0d out of range", m_tid));
            else if (qd[m_tid].size() == 0)
                fail($sformatf("beat %h with m_tid_o=%0d that input %0d did not send", m_tdata,
                               m_tid, m_tid));
            else begin
                logic [W-1:0] d;
                bit           l;
                d = qd[m_tid].pop_front();
                l = ql[m_tid].pop_front();
                if (m_tdata !== d || m_tlast !== l)
                    fail($sformatf("m_tid_o=%0d beat data=%h last=%b, expected data=%h last=%b",
                                   m_tid, m_tdata, m_tlast, d, l));
            end
            if (out_open && int'(m_tid) != out_cur)
                fail($sformatf("switched from input %0d to %0d inside a packet", out_cur, m_tid));
            if (!out_open) begin
                npkts++;
                ph_pkts++;
                if (allvalid && ph_pkts >= 3 && int'(m_tid) != (prev_tid + 1) % N)
                    fail($sformatf("all inputs valid: packet from %0d followed by %0d", prev_tid,
                                   m_tid));
                prev_tid = m_tid;
            end
            if (fullrate && ph_pkts >= 2 && last_hs_ok &&
                (out_open ? cycle - last_hs != 1 : cycle - last_hs > 2))
                fail($sformatf("full rate: %0d cycles between beats (%s)", cycle - last_hs,
                               out_open ? "within a packet" : "between packets"));
            last_hs = cycle;
            last_hs_ok = 1;
            out_open = !m_tlast;
            out_cur = m_tid;
            nbeats++;
            idle = 0;
        end else begin
            if (m_tvalid === 1'b1) nstall++;
            expect_move = m_tvalid === 1'b1 || (in_open ? s_tvalid[in_cur] : |s_tvalid);
            if (m_tready && expect_move && ++idle > 32)
                fail("no beat moves for 32 cycles with m_tready_i high");
        end
        prev_v = m_tvalid;
        prev_r = m_tready;
        prev_d = m_tdata;
        prev_l = m_tlast;
        prev_id = m_tid;
    endtask

    task automatic set_phase(int k);
        allvalid = 0;
        fullrate = 0;
        ph_pkts = 0;
        last_hs_ok = 0;
        for (int i = 0; i < N; i++) pv[i] = 60;
        pr = 70;
        case (k)
            1: begin allvalid = 1; fullrate = 1; end
            2: begin allvalid = 1; pr = 50; end
            3: begin for (int i = 0; i < N; i++) pv[i] = 3; pr = 80; end
            4: begin  // the last input waits behind always-busy others
                for (int i = 0; i < N - 1; i++) pv[i] = 100;
                pv[N-1] = 10;
                pr = 60;
            end
            5: begin for (int i = 0; i < N; i++) pv[i] = 80; pr = 20; end
            default: ;
        endcase
    endtask

    initial begin
        bit did_reset = 0;
        clear_model();
        stop = 0;
        set_phase(0);
        #17 rst_n = 1'b1;
        for (int c = 0; c < Cycles; c++) begin
            @(negedge clk);
            if (c % 400 == 0) set_phase((c / 400) % 6);
            if (!did_reset && c > Cycles / 2 && out_open && !allvalid) begin
                did_reset = 1;
                rst_n = 1'b0;
                s_tvalid = '0;
                m_tready = 1'b0;
                clear_model();
                #1 if (m_tvalid !== 1'b0) fail("m_tvalid_o not 0 in reset");
                @(posedge clk);
                @(negedge clk);
                rst_n = 1'b1;
            end
            drive();
            #1 sample();
            @(posedge clk) cycle++;
        end
        stop = 1;
        allvalid = 0;
        fullrate = 0;
        for (int c = 0; c < 300; c++) begin
            bit busy = 0;
            @(negedge clk);
            drive();
            #1 sample();
            @(posedge clk) cycle++;
            for (int i = 0; i < N; i++) if (rem[i] != 0 || qd[i].size() != 0) busy = 1;
            if (!busy && !m_tvalid) break;
        end
        for (int i = 0; i < N; i++)
            if (rem[i] != 0 || qd[i].size() != 0)
                fail($sformatf("input %0d: %0d beats never sent at the end", i,
                               rem[i] + qd[i].size()));
        if (!did_reset || npkts < 3500 || nstall < 1000)
            fail($sformatf("weak run: reset=%0d packets=%0d stalls=%0d", did_reset, npkts,
                           nstall));
        done = 1;
    end
endmodule

module pkt_arbiter_tb;
    pkt_arbiter_tb_bench #(.N(4), .W(16)) u_b4 ();
    pkt_arbiter_tb_bench #(.N(3), .W(8)) u_b3 ();

    initial begin
        #2000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    initial begin
        wait (u_b4.done && u_b3.done);
        if (u_b4.errors + u_b3.errors == 0) $display("EQUIV PASS");
        else
            $display("EQUIV FAIL: %0d errors, first at %s", u_b4.errors + u_b3.errors,
                     u_b4.errors ? u_b4.first : u_b3.first);
        $finish;
    end
endmodule
