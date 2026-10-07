// Grader harness for eval 135: checks irq_ctrl at Sources = 1, 8 and 31 against
// a cycle-accurate model of the prompt; irq_o is compared on every cycle and
// reg_rdata_o in the cycle after each read. Directed sequences (reset values of
// every aligned address, all-ones writes and read-back, read-only pending,
// unmapped addresses, level/edge sources, ties, threshold equal to priority,
// priority 0, disabled sources, completes of ids not in service) are followed
// by random register traffic with random sources, and one asynchronous reset
// in the middle. Coverage counters make sure every case was really hit.
// Decisions where the prompt leaves room:
// - A claim picks from the state at the read edge: a pending bit set in that
//   same edge is not visible to it. The claimed source is in service from the
//   read edge, so a level source still high does not stay pending; the harness
//   never gives the claimed source a rising edge in the claim edge itself.
// - Pending is sticky: a level source that drops stays pending until claimed.
//   Pending sets regardless of enable and priority.
// - In service, a rising edge of an edge-mode source is remembered (one only)
//   and becomes pending after the complete; a level source still high re-pends.
//   Whether that happens in the complete edge or the next one is left open:
//   the completed source's src_i is held in the complete edge and the next,
//   the cycle after a complete has no claim, and irq_o is not compared in the
//   one cycle where the two timings differ; a pending read in the edge after a
//   complete does not score the completed source's bit.
// - irq_o is a register of "some pending, enabled source has priority above
//   the threshold" (strictly above; equal does not interrupt).
// - Read data of the pending register may show the state before or after the
//   read edge; all other registers do not change in a read cycle. The claim id
//   must be exact. reg_rdata_o is not checked outside the cycle after a read.
// - Only word-aligned addresses are used, reg_we_i and reg_re_i are never high
//   together, completes write values below 2**$clog2(Sources+1), and the mode
//   register is written only while no source is in service.
// - src_i is held low in reset (so an edge in the first cycle after is a real one).
// Parameter range errors (Sources outside 1..31) are not exercised here.
module irq_ctrl_chk #(
    parameter int S = 8,
    parameter int Cycles = 40000
) (
    output bit    finished,
    output int    errors,
    output string first
);
    localparam logic [31:0] Mask = (32'd1 << S) - 1;
    localparam int IW = $clog2(S + 1);
    localparam logic [31:0] IdMask = (32'd1 << IW) - 1;

    logic         clk = 1'b0;
    logic         rst_n = 1'b0;
    logic         we = 1'b0;
    logic         re = 1'b0;
    logic [7:0]   addr = '0;
    logic [31:0]  wdata = '0;
    logic [S-1:0] src = '0;
    logic [31:0]  rdata;
    logic         irq;

    irq_ctrl #(.Sources(S)) u_dut (
        .clk_i(clk), .rst_ni(rst_n), .src_i(src), .reg_we_i(we), .reg_re_i(re),
        .reg_addr_i(addr), .reg_wdata_i(wdata), .reg_rdata_o(rdata), .irq_o(irq)
    );

    always #5 clk = ~clk;

    // Model state.
    logic [2:0]  m_prio[32];
    logic [31:0] m_pend, m_en, m_mode, m_insvc, m_mem, m_prev;
    logic [2:0]  m_thr;
    logic        m_irq;
    // Harness state.
    int          cycle = 0;
    bit          rd_chk = 0;
    logic [31:0] rd_a, rd_b;
    logic [7:0]  rd_addr;
    logic [31:0] rd_amb = '0;    // pending bits completed one edge before the read
    logic [1:0]  skip = '0;      // bit 1: completed two edges ago, irq_o not compared
    logic [31:0] hold = '0;      // src bits held in the next edge
    logic [31:0] last_cmpl = '0;
    bit          no_claim = 0;
    int cov_tie = 0, cov_thr_eq = 0, cov_p0 = 0, cov_dis = 0, cov_mem = 0, cov_mem2 = 0;
    int cov_lvl = 0, cov_badc = 0, cov_sticky = 0, cov_unm = 0, cov_claims = 0, cov_rst = 0;

    initial begin
        errors = 0;
        first = "";
        finished = 0;
    end

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("Sources=%0d cycle %0d: %s", S, cycle, msg);
        errors++;
    endtask

    task automatic model_reset();
        for (int i = 0; i < 32; i++) m_prio[i] = '0;
        {m_pend, m_en, m_mode, m_insvc, m_mem, m_prev} = '0;
        m_thr = '0;
        m_irq = 1'b0;
        rd_chk = 0;
        skip = '0;
        hold = '0;
        last_cmpl = '0;
        no_claim = 0;
    endtask

    function automatic int best();
        int id = 0;
        logic [2:0] bp = '0;
        for (int i = 0; i < S; i++)
            if (m_pend[i] && m_en[i] && m_prio[i] > m_thr && (id == 0 || m_prio[i] > bp)) begin
                id = i + 1;
                bp = m_prio[i];
            end
        return id;
    endfunction

    function automatic logic [31:0] regval(logic [7:0] a, int id);
        if (a < 8'(4 * S)) return 32'(m_prio[a[6:2]]);
        case (a)
            8'h80: return m_pend;
            8'h84: return m_en;
            8'h88: return m_mode;
            8'h8C: return 32'(m_thr);
            8'h90: return 32'(id);
            default: return '0;
        endcase
    endfunction

    task automatic check();
        if (!skip[1] && irq !== m_irq) fail($sformatf("irq_o exp=%b dut=%b", m_irq, irq));
        if (rd_chk && (rdata & ~rd_amb) !== (rd_a & ~rd_amb)
            && (rdata & ~rd_amb) !== (rd_b & ~rd_amb)) begin
            if (rd_addr == 8'h80)
                fail($sformatf("read of 0x80 exp=%h (or %h) dut=%h", rd_a, rd_b, rdata));
            else fail($sformatf("read of 0x%h exp=%h dut=%h", rd_addr, rd_a, rdata));
        end
    endtask

    // Model one clock edge with the inputs that were sampled there.
    task automatic update(logic w, logic r, logic [7:0] a, logic [31:0] d, logic [31:0] s,
                          logic [31:0] cmpl);
        int          id;
        logic [31:0] rise, set, cbit, live, cand;
        logic [2:0]  top;
        rise = s & ~m_prev;
        id   = (r && a == 8'h90) ? best() : 0;
        cbit = id != 0 ? 32'd1 << (id - 1) : '0;
        live = '0;
        for (int i = 0; i < S; i++) live[i] = m_pend[i] && m_en[i] && m_prio[i] > m_thr;
        if (r) begin
            rd_chk  = 1;
            rd_addr = a;
            rd_a    = regval(a, id);
            rd_amb  = a == 8'h80 ? last_cmpl : '0;
            if (a >= 8'(4 * S) && a != 8'h80 && a != 8'h84 && a != 8'h88 && a != 8'h8C
                && a != 8'h90) cov_unm++;
        end else rd_chk = 0;
        // Coverage.
        if (r && a == 8'h90) begin
            cov_claims++;
            cand = '0;
            top = id != 0 ? m_prio[id-1] : '0;
            for (int i = 0; i < S; i++) cand[i] = live[i] && m_prio[i] == top;
            if (id != 0 && $countones(cand) > 1) cov_tie++;
            for (int i = 0; i < S; i++) begin
                if (m_pend[i] && m_en[i] && m_thr != 0 && m_prio[i] == m_thr) cov_thr_eq++;
                if (m_pend[i] && m_en[i] && m_thr == 0 && m_prio[i] == 0) cov_p0++;
                if (m_pend[i] && !m_en[i] && m_prio[i] > m_thr) cov_dis++;
            end
        end
        if (w && a == 8'h90 && cmpl == 0) cov_badc++;
        if ((m_mem & ~m_insvc) != 0) cov_mem++;
        if ((m_mem & m_insvc & m_mode & rise) != 0) cov_mem2++;
        if ((last_cmpl & ~m_mode & s) != 0) cov_lvl++;
        if ((m_pend & ~m_mode & ~s & Mask) != 0) cov_sticky++;
        // Next state.
        set     = ~m_insvc & ((m_mode & rise) | (~m_mode & s) | m_mem) & Mask;
        m_irq   = live != 0;
        m_mem   = m_insvc & (m_mem | (m_mode & rise));
        m_pend  = (m_pend | set) & ~cbit;
        m_insvc = (m_insvc & ~cmpl) | cbit;
        m_prev  = s;
        if (w) begin
            if (a < 8'(4 * S)) m_prio[a[6:2]] = d[2:0];
            case (a)
                8'h84: m_en = d & Mask;
                8'h88: m_mode = d & Mask;
                8'h8C: m_thr = d[2:0];
                default: ;
            endcase
        end
        rd_b = (r && a == 8'h80) ? m_pend : rd_a;
        skip = {skip[0], cmpl != 0};
        last_cmpl = cmpl;
        hold = cmpl;
        no_claim = cmpl != 0;
    endtask

    // One cycle, called at a negedge (or just after one): check the outputs,
    // drive the inputs (made legal for the harness rules), model the posedge.
    task automatic cyc(logic w, logic r, logic [7:0] a, logic [31:0] d, logic [31:0] s);
        logic [31:0] cmpl = '0;
        check();
        a[1:0] = 2'b00;
        if (w && r) r = 0;
        if (w && a == 8'h88 && (m_insvc | m_mem) != 0) w = 0;
        if (w && a == 8'h90) d &= IdMask;
        if (r && a == 8'h90 && no_claim) r = 0;
        s = s & Mask;
        s = (s & ~hold) | (m_prev & hold);
        if (r && a == 8'h90 && best() != 0) s[best()-1] = m_prev[best()-1];
        if (w && a == 8'h90 && d >= 1 && d <= S && m_insvc[d-1]) begin
            cmpl = 32'd1 << (d - 1);
            s = (s & ~cmpl) | (m_prev & cmpl);
        end
        we = w;
        re = r;
        addr = a;
        wdata = d;
        src = s[S-1:0];
        @(posedge clk);
        cycle++;
        update(w, r, a, d, s, cmpl);
        @(negedge clk);
    endtask

    // Directed sequence as a list of operations: few cyc call sites keep the
    // build fast, since tasks are inlined.
    typedef struct {
        logic        w, r;
        logic [7:0]  a;
        logic [31:0] d, s;
        int          n;
    } op_t;
    op_t ops[$];

    function automatic void idle(int n, logic [31:0] s);
        ops.push_back('{1'b0, 1'b0, 8'h00, 32'h0, s, n});
    endfunction
    function automatic void wr(logic [7:0] a, logic [31:0] d, logic [31:0] s);
        ops.push_back('{1'b1, 1'b0, a, d, s, 1});
    endfunction
    function automatic void rd(logic [7:0] a, logic [31:0] s);
        ops.push_back('{1'b0, 1'b1, a, 32'h0, s, 1});
    endfunction

    task automatic do_reset();
        check();
        we = 0;
        re = 0;
        src = '0;
        #2 rst_n = 1'b0;
        #1 if (irq !== 1'b0) fail("irq_o not cleared by reset");
        if ((m_pend | m_insvc) != 0) cov_rst++;
        model_reset();
        repeat (2) begin
            @(posedge clk);
            cycle++;
            #1 if (irq !== 1'b0) fail("irq_o not held low in reset");
        end
        @(negedge clk);
        #2 rst_n = 1'b1;
    endtask

    // Random register traffic with random sources.
    function automatic op_t rand_op(int toggle_pct);
        logic [31:0] s = m_prev;
        logic        w = 1'b0, r = 1'b0;
        logic [7:0]  a = '0;
        logic [31:0] d = $urandom;
        int k;
        for (int i = 0; i < S; i++) if ($urandom_range(99) < toggle_pct) s[i] = ~s[i];
        k = $urandom_range(99);
        if (k < 30) ;
        else if (k < 46) {r, a} = {1'b1, 8'h90};
        else if (k < 62) begin
            {w, a} = {1'b1, 8'h90};
            if (m_insvc != 0 && $urandom_range(9) < 8) begin
                int i;
                do i = $urandom_range(S - 1); while (!m_insvc[i]);
                d = i + 1;
            end
        end else if (k < 70) {r, a} = {1'b1, 8'($urandom_range(36) * 4)};
        else if (k < 77) begin
            {w, a} = {1'b1, 8'($urandom_range(S - 1) * 4)};
            if ($urandom_range(3) == 0) d[2:0] = m_thr;
        end else if (k < 81) begin
            {w, a} = {1'b1, 8'h84};
            if ($urandom_range(3) != 0) d = 32'hFFFF_FFFF;
        end else if (k < 83) {w, a} = {1'b1, 8'h88};
        else if (k < 87) begin
            {w, a} = {1'b1, 8'h8C};
            if ($urandom_range(3) != 0) d = $urandom_range(3);
        end else if (k < 90) {w, a} = {1'b1, 8'($urandom_range(63) * 4)};
        else {r, a} = {1'b1, 8'h80};
        return '{w, r, a, d, s, 1};
    endfunction

    initial begin
        int last = S;
        int two = S > 1 ? 2 : 1;
        logic [31:0] b1 = 32'd1;
        logic [31:0] bl = 32'd1 << (S - 1);
        logic [31:0] b2 = 32'd1 << (two - 1);
        model_reset();
        #17 rst_n = 1'b1;
        @(negedge clk);
        // Reset values of every aligned address, then all-ones writes and read-back.
        for (int a = 0; a < 256; a += 4) rd(8'(a), '0);
        for (int a = 0; a < 256; a += 4) if (a != 8'h90) wr(8'(a), 32'hFFFF_FFFF, '0);
        for (int a = 0; a < 256; a += 4) if (a != 8'h90) rd(8'(a), '0);
        wr(8'h88, '0, '0);
        wr(8'h8C, '0, '0);
        // Level source 1: pending is sticky after src_i drops; claim; high while
        // in service does not pend; complete re-pends while still high.
        wr(8'h00, 3, b1);
        idle(2, b1);
        idle(3, '0);
        rd(8'h80, '0);
        rd(8'h90, '0);
        rd(8'h80, b1);
        idle(4, b1);
        rd(8'h80, b1);
        rd(8'h90, b1);  // nothing pending: 0
        wr(8'h90, 1, b1);
        idle(2, b1);
        rd(8'h80, b1);
        rd(8'h90, '0);
        wr(8'h90, 1, '0);
        idle(3, '0);
        rd(8'h90, '0);
        // Edge source last: two rises in service, one remembered.
        wr(8'h88, bl, '0);
        wr(8'(4 * (last - 1)), 7, bl);
        idle(3, bl);
        idle(1, '0);
        rd(8'h90, '0);
        idle(1, bl);
        idle(1, '0);
        idle(1, bl);
        idle(2, '0);
        wr(8'h90, last, '0);
        idle(2, '0);
        rd(8'h80, '0);
        rd(8'h90, '0);
        wr(8'h90, last, '0);
        idle(3, '0);
        rd(8'h90, '0);
        wr(8'h88, '0, '0);
        // Ties, threshold equal to priority, priority 0, disabled source.
        wr(8'h00, 5, '0);
        wr(8'(4 * (two - 1)), 5, '0);
        idle(1, b1 | b2);
        idle(1, '0);
        wr(8'h8C, 5, '0);
        idle(3, '0);
        rd(8'h90, '0);
        wr(8'h8C, 4, '0);
        idle(3, '0);
        rd(8'h90, '0);
        rd(8'h90, '0);
        wr(8'h90, 0, '0);
        wr(8'h90, S + 1, '0);
        wr(8'h90, two, '0);
        wr(8'h90, 1, '0);
        wr(8'h90, 1, '0);
        wr(8'h8C, 0, '0);
        wr(8'h00, 0, b1);
        idle(3, '0);
        rd(8'h90, '0);
        wr(8'h00, 2, '0);
        wr(8'h84, ~b1, '0);
        idle(3, '0);
        rd(8'h90, '0);
        wr(8'h80, 0, '0);
        rd(8'h80, '0);
        wr(8'h84, '1, '0);
        idle(3, '0);
        rd(8'h90, '0);
        wr(8'h90, 1, '0);
        idle(3, '0);
        // Then random traffic with one asynchronous reset in the middle, then idle.
        for (int i = 0; i < ops.size() + Cycles + 2; i++) begin
            op_t o;
            int  j;
            j = i - ops.size();
            if (j < 0) o = ops[i];
            else if (j >= Cycles) o = '{1'b0, 1'b0, 8'h00, 32'h0, 32'h0, 1};
            else begin
                if (j == Cycles / 2) do_reset();
                // Source activity: fast, medium and slow toggling phases.
                o = rand_op((j / 1500) % 3 == 0 ? 40 : (j / 1500) % 3 == 1 ? 8 : 2);
            end
            repeat (o.n) cyc(o.w, o.r, o.a, o.d, o.s);
        end
        if (cov_rst == 0 || cov_thr_eq == 0 || cov_p0 == 0 || cov_dis == 0 || cov_mem == 0
            || cov_mem2 == 0 || cov_lvl == 0 || cov_badc == 0 || cov_sticky == 0 || cov_unm == 0
            || cov_claims < 1000 || (S > 1 && cov_tie == 0))
            fail($sformatf({"harness coverage hole: rst %0d thr_eq %0d p0 %0d dis %0d mem %0d ",
                            "mem2 %0d lvl %0d badc %0d sticky %0d unm %0d claims %0d tie %0d"},
                           cov_rst, cov_thr_eq, cov_p0, cov_dis, cov_mem, cov_mem2, cov_lvl,
                           cov_badc, cov_sticky, cov_unm, cov_claims, cov_tie));
        finished = 1;
    end
endmodule

module irq_ctrl_tb;
    bit    fin1, fin8, fin31;
    int    err1, err8, err31;
    string first1, first8, first31;

    irq_ctrl_chk #(.S(1)) u_s1 (.finished(fin1), .errors(err1), .first(first1));
    irq_ctrl_chk #(.S(8)) u_s8 (.finished(fin8), .errors(err8), .first(first8));
    irq_ctrl_chk #(.S(31)) u_s31 (.finished(fin31), .errors(err31), .first(first31));

    initial begin
        #5000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    initial begin
        wait (fin1 && fin8 && fin31);
        if (err1 + err8 + err31 == 0) $display("EQUIV PASS");
        else
            $display("EQUIV FAIL: %0d errors, first at %s", err1 + err8 + err31,
                     err1 ? first1 : err8 ? first8 : first31);
        $finish;
    end
endmodule
