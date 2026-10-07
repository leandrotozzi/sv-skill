// Grader harness for eval 132: checks i2c_master behaviour against the prompt
// for ClkDiv 4, 5, 13 and the default 250, on a wired-AND bus with a
// behavioural slave (7-bit address, register pointer, auto-increment, random
// NACKs of written data, SCL stretching after random falls). Commands come as
// legal transactions: write, write-pointer + repeated START + read, current
// address read and wrong address, ended by STOP or by a repeated START.
// Bus checks, sampled once per cycle: SDA changes while SCL is high only as
// the START/STOP condition of a START/STOP command (an SDA change in the same
// cycle as an SCL edge is allowed); bytes MSB first, ACK slot values both
// ways; SCL rises only inside a command (9 per WRITE/READ, 1 per STOP and
// repeated START, none for START from idle). Timing, in cycles of the wired
// SCL: every low phase >= ClkDiv; a data high phase ClkDiv..ClkDiv+4 (one
// less allowed when the slave ends a stretch, as the master sees the line
// rise only at its next edge), a repeated START high phase ClkDiv..2*ClkDiv+4;
// a low phase inside a WRITE/READ at most max(ClkDiv, stretch)+4, one that
// spans a command acceptance at most 2*ClkDiv+4 after it. Handshake: one
// rsp_valid_o per accepted command, cmd_ready_o low from the cycle after
// acceptance until rsp_valid_o; nack_o (WRITE) and rdata_o (READ) at
// rsp_valid_o; ack_i/wdata_i/cmd_i change to junk right after acceptance.
// Both _oe_o low in and out of reset and after STOP until the next START. An
// asynchronous reset hits once mid-WRITE.
module i2c_master_tb_unit #(
    parameter int Div        = 4,
    parameter bit UseDefault = 1'b0,
    parameter int NumTxns    = 300
);
    localparam int Tol = 4;
    localparam int Budget = 9 * (6 * Div + 2 * Tol + 4) + 6 * Div + 60;
    localparam logic [6:0] Addr = 7'h5A;
    localparam logic [1:0] Start = 2'd0, Stop = 2'd1, Write = 2'd2, Read = 2'd3;

    typedef struct packed {
        logic [1:0] c;
        logic [7:0] d;
        logic       a;
    } cmd_t;

    logic       clk = 1'b0;
    logic       rst_n = 1'b0;
    logic       cmd_valid = 1'b0;
    logic [1:0] cmd = '0;
    logic [7:0] wdata = '0;
    logic       ack = 1'b0;
    logic       cmd_ready, rsp_valid, nack;
    logic [7:0] rdata;
    logic       m_scl_oe, m_sda_oe;
    logic       s_scl_oe = 1'b0, s_sda_oe = 1'b0;
    logic       scl, sda;

    assign scl = !(m_scl_oe || s_scl_oe);
    assign sda = !(m_sda_oe || s_sda_oe);

    if (UseDefault) begin : g_default
        i2c_master u_dut (
            .clk_i(clk), .rst_ni(rst_n), .cmd_valid_i(cmd_valid), .cmd_ready_o(cmd_ready),
            .cmd_i(cmd), .wdata_i(wdata), .ack_i(ack), .rsp_valid_o(rsp_valid), .rdata_o(rdata),
            .nack_o(nack), .scl_i(scl), .scl_oe_o(m_scl_oe), .sda_i(sda), .sda_oe_o(m_sda_oe)
        );
    end else begin : g_param
        i2c_master #(.ClkDiv(Div)) u_dut (
            .clk_i(clk), .rst_ni(rst_n), .cmd_valid_i(cmd_valid), .cmd_ready_o(cmd_ready),
            .cmd_i(cmd), .wdata_i(wdata), .ack_i(ack), .rsp_valid_o(rsp_valid), .rdata_o(rdata),
            .nack_o(nack), .scl_i(scl), .scl_oe_o(m_scl_oe), .sda_i(sda), .sda_oe_o(m_sda_oe)
        );
    end

    always #5 clk = ~clk;

    int    errors = 0;
    string first = "";
    bit    finished = 0;
    int    cycle = 0;

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("ClkDiv %0d, cycle %0d: %s", Div, cycle, msg);
        errors++;
    endtask

    function automatic string cname(logic [1:0] c);
        case (c)
            Start:   return "START";
            Stop:    return "STOP";
            Write:   return "WRITE";
            default: return "READ";
        endcase
    endfunction

    function automatic string ackname(bit a);
        return a ? "ACK" : "NACK";
    endfunction

    // ---------------------------------------------------------------- slave
    typedef enum int {SIdle, SAddr, SWr, SRd} smode_e;
    logic [7:0] mem[256];
    smode_e     s_mode = SIdle;
    logic [7:0] s_ptr = '0, s_tx = '0;
    bit         s_rw = 0, s_got_ptr = 0, s_ack = 0;
    bit         sda_pend = 0;
    int         sda_due;
    logic       sda_next;
    int         scl_rel = 0;
    logic [7:0] last_rd_byte = '0;   // byte the slave sent in the last READ frame
    bit         last_wr_ack = 0;     // slave's answer to the last byte it received

    task automatic slave_sda(logic pull);
        sda_pend = 1;
        sda_due  = cycle + 1 + (Div > 4 ? $urandom % (Div - 3) : 0);
        sda_next = pull;
    endtask

    task automatic slave_reset();
        s_mode   = SIdle;
        s_scl_oe = 1'b0;
        s_sda_oe = 1'b0;
        sda_pend = 0;
    endtask

    // ------------------------------------------------- command tracking
    cmd_t q[$];        // commands still to offer
    cmd_t dq[$];       // accepted WRITE/READ whose 9 bits are not all seen
    bit   in_prog = 0;
    cmd_t cur;
    int   acc_cycle, rises, starts, stops;
    bit   from_idle;
    bit   bus_free = 1;  // after reset or STOP, until a START is accepted
    int   pend_cycles = 0;
    int   num_txns = 0, num_rsp = 0;
    int   cov_stretch = 0, cov_rs = 0, cov_wnack = 0, cov_badaddr = 0, cov_rack = 0;
    int   cov_rnack = 0, cov_free_start = 0;
    bit   did_reset = 0;
    int   rst_release = -1;

    // ----------------------------------------------------- bus monitor
    logic p_scl = 1'b1, p_sda = 1'b1, p_mscl = 1'b0;
    bit   hi_from_idle = 1, hi_has_start = 0, hi_slave_rise = 0, lo_valid = 0;
    bit   acc_in_low = 0, acc_in_high = 0;
    int   hi_start = 0, lo_start = 0, last_acc = 0, stretch_rise = 0;
    int   bitn = 0;
    logic [7:0] sh = '0;
    bit   bus_active = 0;

    task automatic resync();
        p_scl = scl;
        p_sda = sda;
        p_mscl = m_scl_oe;
        hi_from_idle = 1;
        hi_has_start = 0;
        lo_valid = 0;
        bus_active = 0;
        bitn = 0;
    endtask

    task automatic on_accept();
        cur = cmd_t'({cmd, wdata, ack});
        in_prog = 1;
        acc_cycle = cycle;
        rises = 0;
        starts = 0;
        stops = 0;
        from_idle = bus_free;
        if (cmd == Start) bus_free = 0;
        if (cmd == Write || cmd == Read) dq.push_back(cur);
        acc_in_low = 1;
        acc_in_high = 1;
        last_acc = cycle;
    endtask

    // The slave and the frame checker at an SCL fall; b is SDA during the high phase.
    task automatic on_bit(logic b);
        int i = bitn;
        if (i < 8) begin
            sh = {sh[6:0], b};
            bitn++;
            if (s_mode == SRd) begin
                if (i < 7) slave_sda(!s_tx[6-i]);
                else begin
                    slave_sda(1'b0);
                    last_rd_byte = s_tx;
                end
            end
            if (bitn == 8) begin
                if (s_mode == SAddr || s_mode == SWr) begin
                    if (s_mode == SAddr) begin
                        s_ack = sh[7:1] == Addr;
                        s_rw  = sh[0];
                    end else if (!s_got_ptr) begin
                        s_ack = 1;
                        s_ptr = sh;
                        s_got_ptr = 1;
                    end else begin
                        s_ack = $urandom % 6 != 0;
                        if (s_ack) begin
                            mem[s_ptr] = sh;
                            s_ptr++;
                        end
                    end
                    last_wr_ack = s_ack;
                    slave_sda(s_ack);
                end else if (s_mode == SIdle) last_wr_ack = 0;
                // Byte check against the oldest pending WRITE/READ.
                if (dq.size() == 0) fail($sformatf("8 data bits (%h) clocked with no WRITE/READ", sh));
                else if (dq[0].c == Write && sh !== dq[0].d)
                    fail($sformatf("WRITE %h: bus carried %h (MSB first expected)", dq[0].d, sh));
                else if (dq[0].c == Read && sh !== last_rd_byte)
                    fail($sformatf("READ: slave sent %h, bus carried %h", last_rd_byte, sh));
            end
        end else begin
            // ACK slot ends.
            bitn = 0;
            if (dq.size() != 0) begin
                if (dq[0].c == Write && b !== !last_wr_ack)
                    fail($sformatf("WRITE %h: SDA %b in the ACK slot, slave answered %s", dq[0].d,
                                   b, ackname(last_wr_ack)));
                if (dq[0].c == Read && b !== !dq[0].a)
                    fail($sformatf("READ with ack_i %b: master put %s on the bus", dq[0].a,
                                   ackname(!b)));
                if (dq[0].c == Read) begin
                    if (dq[0].a) cov_rack++;
                    else cov_rnack++;
                end
                void'(dq.pop_front());
            end
            case (s_mode)
                SAddr: begin
                    if (!s_ack) begin
                        s_mode = SIdle;
                        cov_badaddr++;
                        slave_sda(1'b0);
                    end else if (s_rw) begin
                        s_mode = SRd;
                        s_tx = mem[s_ptr];
                        slave_sda(!s_tx[7]);
                    end else begin
                        s_mode = SWr;
                        s_got_ptr = 0;
                        slave_sda(1'b0);
                    end
                end
                SWr: begin
                    if (!s_ack) cov_wnack++;
                    slave_sda(1'b0);
                end
                SRd: begin
                    if (b == 1'b0) begin
                        s_ptr++;
                        s_tx = mem[s_ptr];
                        slave_sda(!s_tx[7]);
                    end else begin
                        s_mode = SIdle;
                        slave_sda(1'b0);
                    end
                end
                default: ;
            endcase
        end
    endtask

    task automatic monitor();
        if (p_scl && scl && sda !== p_sda) begin
            if (sda == 1'b0) begin
                if (!(in_prog && cur.c == Start))
                    fail(in_prog ? $sformatf("SDA fell while SCL high during %s", cname(cur.c))
                                 : "START condition with no START command");
                starts++;
                hi_has_start = 1;
                bus_active = 1;
                bitn = 0;
                s_mode = SAddr;
                if (!hi_from_idle) cov_rs++;
                else cov_free_start++;
            end else begin
                if (!(in_prog && cur.c == Stop))
                    fail(in_prog ? $sformatf("SDA rose while SCL high during %s", cname(cur.c))
                                 : "STOP condition with no STOP command");
                stops++;
                bus_active = 0;
                hi_from_idle = 1;
                s_mode = SIdle;
            end
        end
        if (!p_scl && scl) begin
            if (!in_prog) fail("SCL rose with no command in progress");
            rises++;
            if (lo_valid) begin
                int len = cycle - lo_start;
                if (len < Div) fail($sformatf("SCL low phase of %0d cycles", len));
                if (acc_in_low) begin
                    int base = (last_acc > lo_start ? last_acc : lo_start) + 2 * Div;
                    if (cycle > (base > stretch_rise ? base : stretch_rise) + Tol)
                        fail($sformatf("SCL low phase of %0d cycles (%0d after the command)",
                                       len, cycle - last_acc));
                end else if (cycle > (lo_start + Div > stretch_rise ? lo_start + Div
                                                                    : stretch_rise) + Tol)
                    fail($sformatf("SCL low phase of %0d cycles within a byte (stretch to %0d)",
                                   len, stretch_rise - lo_start));
            end
            hi_start = cycle;
            hi_from_idle = 0;
            hi_has_start = 0;
            hi_slave_rise = !p_mscl;
            acc_in_low = 0;
            acc_in_high = 0;
        end
        if (p_scl && !scl) begin
            if (hi_from_idle) begin
                if (!hi_has_start) fail("SCL pulled low with the bus idle (no START)");
            end else begin
                int len = cycle - hi_start;
                int lim = hi_has_start ? 2 * Div : Div;
                if (len < Div - hi_slave_rise)
                    fail($sformatf("SCL high phase of %0d cycles%s", len,
                                   hi_slave_rise ? string'(" after a stretch") : string'("")));
                if (acc_in_high ? cycle > (hi_start + lim > last_acc + 2 * Div ? hi_start + lim
                                           : last_acc + 2 * Div) + Tol
                                : len > lim + Tol)
                    fail($sformatf("SCL high phase of %0d cycles%s", len,
                                   hi_has_start ? string'(" (repeated START)") : string'("")));
            end
            lo_start = cycle;
            lo_valid = 1;
            stretch_rise = 0;
            if (bus_active && !hi_has_start) on_bit(p_sda);
            // Slave stretch: hold SCL low for a while from this fall.
            if ($urandom % 4 == 0) begin
                int len = 1 + $urandom % (3 * Div);
                s_scl_oe = 1'b1;
                scl_rel = cycle + len;
                stretch_rise = cycle + len + 1;
                if (len >= Div + 1) cov_stretch++;
            end
        end
    endtask

    // Outputs settled after posedge `cycle`; an accepted command was taken at that edge.
    task automatic observe(bit accepted);
        if (!rst_n) begin
            if (m_scl_oe !== 1'b0 || m_sda_oe !== 1'b0 || rsp_valid !== 1'b0)
                fail("scl_oe_o/sda_oe_o/rsp_valid_o not low in reset");
            resync();
            return;
        end
        if ($isunknown({cmd_ready, rsp_valid, m_scl_oe, m_sda_oe}))
            fail("cmd_ready_o/rsp_valid_o/scl_oe_o/sda_oe_o unknown");
        if (accepted) on_accept();
        monitor();
        if (rsp_valid === 1'b1) begin
            num_rsp++;
            if (!in_prog) fail("rsp_valid_o with no command in progress");
            else begin
                case (cur.c)
                    Start: if (starts != 1 || stops != 0 || rises != (from_idle ? 0 : 1))
                        fail($sformatf("START (%s) answered after %0d START, %0d STOP, %0d SCL rises",
                                       from_idle ? string'("from idle") : string'("repeated"), starts, stops, rises));
                    Stop: begin
                        if (starts != 0 || stops != 1 || rises != 1)
                            fail($sformatf("STOP answered after %0d START, %0d STOP, %0d SCL rises",
                                           starts, stops, rises));
                        bus_free = 1;
                    end
                    default: begin
                        if (starts != 0 || stops != 0 || rises != 9)
                            fail($sformatf("%s answered after %0d START, %0d STOP, %0d SCL rises",
                                           cname(cur.c), starts, stops, rises));
                        if (cur.c == Write && nack !== !last_wr_ack)
                            fail($sformatf("WRITE %h: nack_o %b, slave answered %s", cur.d, nack,
                                           ackname(last_wr_ack)));
                        if (cur.c == Read && rdata !== last_rd_byte)
                            fail($sformatf("READ: rdata_o %h, slave sent %h", rdata, last_rd_byte));
                    end
                endcase
                in_prog = 0;
            end
        end else if (in_prog) begin
            if (cmd_ready !== 1'b0) fail($sformatf("cmd_ready_o high during %s", cname(cur.c)));
            if (cycle - acc_cycle > Budget) begin
                fail($sformatf("%s did not finish within %0d cycles", cname(cur.c), Budget));
                in_prog = 0;
            end
        end
        if (bus_free && (m_scl_oe !== 1'b0 || m_sda_oe !== 1'b0))
            fail("scl_oe_o/sda_oe_o not both low after reset or STOP");
        p_scl = scl;
        p_sda = sda;
        p_mscl = m_scl_oe;
    endtask

    task automatic slave_update();
        if (sda_pend && cycle >= sda_due) begin
            s_sda_oe = sda_next;
            sda_pend = 0;
        end
        if (s_scl_oe && cycle >= scl_rel) s_scl_oe = 1'b0;
    endtask

    // ----------------------------------------------------------- driver
    function automatic void push(logic [1:0] c, logic [7:0] d = 8'($urandom), logic a = 1'b0);
        q.push_back(cmd_t'({c, d, a}));
    endfunction

    function automatic void gen_txn();
        int n = 1 + $urandom % 4;
        push(Start);
        case ($urandom % 6)
            0, 1: begin  // write: pointer then data
                push(Write, {Addr, 1'b0});
                push(Write);
                repeat (n - 1) push(Write);
            end
            2, 3: begin  // pointer write, repeated START, read
                push(Write, {Addr, 1'b0});
                push(Write);
                push(Start);
                push(Write, {Addr, 1'b1});
                for (int i = 0; i < n; i++) push(Read, 8'($urandom), i != n - 1);
            end
            4: begin  // current address read
                push(Write, {Addr, 1'b1});
                for (int i = 0; i < n; i++) push(Read, 8'($urandom), i != n - 1);
            end
            default: push(Write, {Addr ^ 7'(1 + $urandom % 127), 1'($urandom)});  // wrong address
        endcase
        if ($urandom % 3 != 0) push(Stop);  // else the next START is a repeated one
        num_txns++;
    endfunction

    int  gap = 0;
    bit  vld_s = 0, rdy_s = 0;

    task automatic drive(bit accepted);
        if (accepted || !cmd_valid) begin
            cmd_valid = 1'b0;
            {cmd, wdata, ack} = 11'($urandom);
            if (q.size() == 0 && num_txns < NumTxns) gen_txn();
            if (q.size() == 0 && num_txns == NumTxns && !bus_free && !in_prog) push(Stop);
            if (q.size() != 0) begin
                if (gap > 0) gap--;
                else begin
                    cmd_t c = q.pop_front();
                    cmd_valid = 1'b1;
                    {cmd, wdata, ack} = c;
                    gap = $urandom % 2 ? 0 : $urandom % (3 * Div);
                end
            end
            pend_cycles = 0;
        end else if (++pend_cycles > Budget + 4 * Div) begin
            fail($sformatf("%s never accepted", cname(cmd)));
            pend_cycles = 0;
        end
    endtask

    task automatic apply_reset();
        rst_n = 1'b0;
        #1;
        if (m_scl_oe !== 1'b0 || m_sda_oe !== 1'b0 || rsp_valid !== 1'b0)
            fail("scl_oe_o/sda_oe_o/rsp_valid_o not cleared by the asynchronous reset");
        did_reset = 1;
        rst_release = cycle + 2;
        slave_reset();
        q.delete();
        dq.delete();
        in_prog = 0;
        bus_free = 1;
        cmd_valid = 1'b0;
        gap = 0;
        resync();
    endtask

    initial begin
        foreach (mem[i]) mem[i] = 8'($urandom);
        #17 rst_n = 1'b1;
    end

    initial begin
        int idle = 0;
        while (idle < 6 * Div + 20) begin
            bit accepted;
            @(posedge clk);
            cycle++;
            #1;
            if (cycle == rst_release) rst_n = 1'b1;
            accepted = vld_s && rdy_s && rst_n;
            observe(accepted);
            slave_update();
            if (rst_n && !did_reset && num_txns > NumTxns / 2 && in_prog && cur.c == Write
                && rises == 3 && s_mode == SWr) begin
                #1 apply_reset();
            end else if (rst_n) drive(accepted);
            idle = (num_txns == NumTxns && q.size() == 0 && !in_prog && !cmd_valid && bus_free)
                   ? idle + 1 : 0;
            #1;
            vld_s = cmd_valid;
            rdy_s = cmd_ready;
        end
        if (!did_reset) fail("harness: reset never applied");
        if (cov_stretch == 0 || cov_rs == 0 || cov_wnack == 0 || cov_badaddr == 0 || cov_rack == 0
            || cov_rnack == 0)
            fail($sformatf("coverage: stretch %0d, repeated START %0d, write NACK %0d, bad address %0d, read ACK %0d / NACK %0d",
                           cov_stretch, cov_rs, cov_wnack, cov_badaddr, cov_rack, cov_rnack));
        finished = 1;
    end
endmodule

module i2c_master_tb;
    i2c_master_tb_unit #(.Div(4), .NumTxns(400)) u_div4 ();
    i2c_master_tb_unit #(.Div(5), .NumTxns(400)) u_div5 ();
    i2c_master_tb_unit #(.Div(13), .NumTxns(150)) u_div13 ();
    i2c_master_tb_unit #(.Div(250), .UseDefault(1'b1), .NumTxns(12)) u_div250 ();

    initial begin
        #400000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    initial begin
        int    errors;
        string first;
        wait (u_div4.finished && u_div5.finished && u_div13.finished && u_div250.finished);
        errors = u_div4.errors + u_div5.errors + u_div13.errors + u_div250.errors;
        first = u_div4.errors ? u_div4.first : u_div5.errors ? u_div5.first
              : u_div13.errors ? u_div13.first : u_div250.first;
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d errors, first at %s", errors, first);
        $finish;
    end
endmodule
