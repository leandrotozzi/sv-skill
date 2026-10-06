// Grader harness for eval 118: an AXI4-Lite master model with a register
// model drives thousands of random writes and reads (AW before W, W before AW,
// together; random valid delays, bready_i/rready_i stalls, masters that wait
// for bvalid_o/rvalid_o before raising ready; wstrb patterns; REG0..2, ID,
// SLVERR addresses with random low bits; garbage on payloads while not valid;
// a new request offered while a response is still pending) plus one reset in
// the middle. Checked: bresp/rresp/rdata against the model, B and R in order
// with none spurious, bvalid_o/rvalid_o held with a stable payload until
// ready, both 0 in reset, and each response valid at most 4 cycles after its
// request is fully presented and the previous response of the same direction
// was accepted. A read is never issued to a register with a write in flight
// (or the other way round), so overlap ordering is not scored.
module axil_regs_tb;
    localparam int Cycles = 40000;
    localparam int MaxTx  = Cycles + 64;
    localparam logic [31:0] Id = 32'h5EC0_0001;

    logic        clk = 1'b0, rst_n = 1'b0;
    logic        awvalid = 1'b0, wvalid = 1'b0, bready = 1'b0;
    logic        arvalid = 1'b0, rready = 1'b0;
    logic [7:0]  awaddr = '0, araddr = '0;
    logic [31:0] wdata = '0;
    logic [3:0]  wstrb = '0;
    logic        awready, wready, bvalid, arready, rvalid;
    logic [1:0]  bresp, rresp;
    logic [31:0] rdata;

    axil_regs u_dut (
        .clk_i(clk), .rst_ni(rst_n),
        .awvalid_i(awvalid), .awready_o(awready), .awaddr_i(awaddr),
        .wvalid_i(wvalid), .wready_o(wready), .wdata_i(wdata), .wstrb_i(wstrb),
        .bvalid_o(bvalid), .bready_i(bready), .bresp_o(bresp),
        .arvalid_i(arvalid), .arready_o(arready), .araddr_i(araddr),
        .rvalid_o(rvalid), .rready_i(rready), .rdata_o(rdata), .rresp_o(rresp)
    );

    always #5 clk = ~clk;

    initial begin
        #5000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    int    errors = 0;
    string first = "";
    int    edge_n = 0;     // posedges so far
    int    base_edge = 0;  // edge of the last reset release

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("edge %0d: %s", edge_n, msg);
        errors++;
    endtask

    // Register model.
    logic [31:0] regs [3];

    function automatic logic [1:0] exp_resp(logic [7:0] a);
        return (a >= 8'h10) ? 2'b10 : 2'b00;
    endfunction

    function automatic logic [31:0] exp_rdata(logic [7:0] a);
        return (a < 8'h0C) ? regs[a[3:2]] : (a < 8'h10) ? Id : 32'h0;
    endfunction

    // Writes: issued nw, B seen nbs, B accepted nb (all in order).
    logic [7:0]  w_addr [MaxTx];
    logic [31:0] w_data [MaxTx];
    logic [3:0]  w_strb [MaxTx];
    int          w_aw_first [MaxTx], w_w_first [MaxTx], w_hs_edge [MaxTx];
    bit          w_aw_acc [MaxTx], w_w_acc [MaxTx], w_late [MaxTx];
    int          nw = 0, nbs = 0, nb = 0, wbase = 0;
    bit          w_pres = 0, b_hold = 0;
    int          aw_wait, w_wait;
    logic [1:0]  held_bresp;

    // Reads: issued nr, R seen nrs, R accepted nrb.
    logic [7:0]  r_addr [MaxTx];
    int          r_first [MaxTx], r_hs_edge [MaxTx];
    bit          r_acc [MaxTx], r_late [MaxTx];
    int          nr = 0, nrs = 0, nrb = 0, rbase = 0;
    bit          r_pres = 0, r_hold = 0;
    int          ar_wait;
    logic [1:0]  held_rresp;
    logic [31:0] held_rdata;

    // Master settings, redrawn every few hundred cycles.
    int bmode, rmode, wstart, rstart, wmax, rmax;
    int num_slverr = 0, num_id_wr = 0, num_partial = 0;

    function automatic logic [7:0] rand_addr();
        case ($urandom % 10)
            0, 1, 2, 3, 4, 5: return 8'($urandom % 16);
            6:       return 8'h0C | 8'($urandom % 4);
            7, 8:    return 8'h10 | 8'($urandom % 4);
            default: return 8'h10 + 8'($urandom % 240);
        endcase
    endfunction

    function automatic bit write_conflict(logic [7:0] a);
        if (a >= 8'h0C) return 0;
        for (int k = nrb; k < nr; k++)
            if (r_addr[k] < 8'h0C && r_addr[k][3:2] == a[3:2]) return 1;
        return 0;
    endfunction

    function automatic bit read_conflict(logic [7:0] a);
        if (a >= 8'h0C) return 0;
        for (int k = nb; k < nw; k++)
            if (w_addr[k] < 8'h0C && w_addr[k][3:2] == a[3:2]) return 1;
        return 0;
    endfunction

    // Outputs as settled after the last posedge (we are at a negedge).
    task automatic observe();
        bit b_new, r_new;
        if ($isunknown({bvalid, rvalid})) fail("bvalid_o/rvalid_o unknown");
        // ---- B channel
        if (b_hold && (bvalid !== 1'b1 || bresp !== held_bresp))
            fail("bvalid_o dropped or bresp_o changed before bready_i");
        b_new = (bvalid === 1'b1) && !b_hold;
        if (!b_new && nbs < nw && !w_late[nbs]) begin
            int prev = (nbs == wbase) ? base_edge : (nb >= nbs ? w_hs_edge[nbs-1] : -1);
            if (prev >= 0 && w_aw_first[nbs] >= 0 && w_w_first[nbs] >= 0) begin
                int p = prev + 1;
                if (w_aw_first[nbs] > p) p = w_aw_first[nbs];
                if (w_w_first[nbs] > p) p = w_w_first[nbs];
                if (edge_n >= p + 3) begin
                    fail($sformatf("no bvalid_o within 4 cycles of the write to 0x%02h", w_addr[nbs]));
                    w_late[nbs] = 1;
                end
            end
        end
        if (b_new) begin
            if (nbs >= nw || !w_aw_acc[nbs] || !w_w_acc[nbs])
                fail("bvalid_o without a complete write");
            else begin
                if (bresp !== exp_resp(w_addr[nbs]))
                    fail($sformatf("write to 0x%02h: bresp %0b, expected %0b", w_addr[nbs], bresp,
                                   exp_resp(w_addr[nbs])));
                nbs++;
                b_hold = 1;
                held_bresp = bresp;
            end
        end
        // ---- R channel
        if (r_hold && (rvalid !== 1'b1 || rresp !== held_rresp || rdata !== held_rdata))
            fail("rvalid_o dropped or rdata_o/rresp_o changed before rready_i");
        r_new = (rvalid === 1'b1) && !r_hold;
        if (!r_new && nrs < nr && !r_late[nrs]) begin
            int prev = (nrs == rbase) ? base_edge : (nrb >= nrs ? r_hs_edge[nrs-1] : -1);
            if (prev >= 0 && r_first[nrs] >= 0) begin
                int p = prev + 1;
                if (r_first[nrs] > p) p = r_first[nrs];
                if (edge_n >= p + 3) begin
                    fail($sformatf("no rvalid_o within 4 cycles of the read of 0x%02h", r_addr[nrs]));
                    r_late[nrs] = 1;
                end
            end
        end
        if (r_new) begin
            if (nrs >= nr || !r_acc[nrs]) fail("rvalid_o without an accepted read");
            else begin
                if (rresp !== exp_resp(r_addr[nrs]) || rdata !== exp_rdata(r_addr[nrs]))
                    fail($sformatf("read of 0x%02h: rdata %08h rresp %0b, expected %08h %0b",
                                   r_addr[nrs], rdata, rresp, exp_rdata(r_addr[nrs]),
                                   exp_resp(r_addr[nrs])));
                nrs++;
                r_hold = 1;
                held_rresp = rresp;
                held_rdata = rdata;
            end
        end
    endtask

    task automatic drive_write(bit drain);
        int cur;
        if (awvalid && w_aw_acc[nw-1]) awvalid = 1'b0;
        if (wvalid && w_w_acc[nw-1]) wvalid = 1'b0;
        if (!w_pres && !drain && nw - nb < wmax && $urandom % 100 < wstart) begin
            logic [7:0] a = rand_addr();
            if (!write_conflict(a)) begin
                cur = nw++;
                w_addr[cur] = a;
                w_data[cur] = $urandom;
                case ($urandom % 4)
                    0: w_strb[cur] = 4'hF;
                    1: w_strb[cur] = 4'b0001 << ($urandom % 4);
                    default: w_strb[cur] = 4'($urandom);
                endcase
                w_aw_first[cur] = -1;
                w_w_first[cur] = -1;
                w_aw_acc[cur] = 0;
                w_w_acc[cur] = 0;
                w_late[cur] = 0;
                w_pres = 1;
                if (a >= 8'h10) num_slverr++;
                else if (a >= 8'h0C) num_id_wr++;
                else if (w_strb[cur] != 4'hF) num_partial++;
                aw_wait = $urandom % 2;
                case ($urandom % 3)
                    0: w_wait = aw_wait;                     // together
                    1: w_wait = aw_wait + 1 + $urandom % 4;  // AW first
                    default: begin                           // W first
                        w_wait = aw_wait;
                        aw_wait = w_wait + 1 + $urandom % 4;
                    end
                endcase
            end
        end
        if (w_pres) begin
            cur = nw - 1;
            if (!awvalid && !w_aw_acc[cur]) begin
                if (aw_wait == 0) awvalid = 1'b1;
                else aw_wait--;
            end
            if (!wvalid && !w_w_acc[cur]) begin
                if (w_wait == 0) wvalid = 1'b1;
                else w_wait--;
            end
        end
        if (awvalid) awaddr = w_addr[nw-1];
        else awaddr = $urandom;
        if (wvalid) begin
            wdata = w_data[nw-1];
            wstrb = w_strb[nw-1];
        end else begin
            wdata = $urandom;
            wstrb = $urandom;
        end
        case (drain ? 0 : bmode)
            0: bready = 1'b1;
            1: bready = $urandom % 2;
            2: bready = (bvalid === 1'b1) && ($urandom % 3 == 0);  // waits for bvalid_o
            default: bready = ($urandom % 6 == 0);
        endcase
    endtask

    task automatic drive_read(bit drain);
        if (arvalid && r_acc[nr-1]) arvalid = 1'b0;
        if (!r_pres && !drain && nr - nrb < rmax && $urandom % 100 < rstart) begin
            logic [7:0] a = rand_addr();
            if (!read_conflict(a)) begin
                r_addr[nr] = a;
                r_first[nr] = -1;
                r_acc[nr] = 0;
                r_late[nr] = 0;
                nr++;
                r_pres = 1;
                ar_wait = ($urandom % 3 == 0) ? $urandom % 3 : 0;
            end
        end
        if (r_pres && !arvalid) begin
            if (ar_wait == 0) arvalid = 1'b1;
            else ar_wait--;
        end
        araddr = arvalid ? r_addr[nr-1] : 8'($urandom);
        case (drain ? 0 : rmode)
            0: rready = 1'b1;
            1: rready = $urandom % 2;
            2: rready = (rvalid === 1'b1) && ($urandom % 3 == 0);  // waits for rvalid_o
            default: rready = ($urandom % 6 == 0);
        endcase
    endtask

    initial begin
        bit did_reset = 0;
        regs = '{default: '0};
        #17 rst_n = 1'b1;
        base_edge = 0;
        for (int i = 0; i < Cycles + 40; i++) begin
            bit drain, aw_hs, w_hs, b_hs, ar_hs, r_hs;
            logic [7:0] a;
            drain = (i >= Cycles);
            @(negedge clk);
            observe();
            if (i % 300 == 0) begin
                bmode = $urandom % 4;
                rmode = $urandom % 4;
                wstart = (i < 600) ? 100 : 10 + $urandom % 91;
                rstart = (i < 600) ? 100 : 10 + $urandom % 91;
                wmax = 1 + $urandom % 2;
                rmax = 1 + $urandom % 2;
            end
            if (!did_reset && i > Cycles / 2 && (w_pres || nb < nw) && r_pres) begin
                // Asynchronous reset in the middle of traffic.
                did_reset = 1;
                awvalid = 1'b0;
                wvalid = 1'b0;
                arvalid = 1'b0;
                bready = 1'b0;
                rready = 1'b0;
                #1 rst_n = 1'b0;
                #1 if (bvalid !== 1'b0 || rvalid !== 1'b0) fail("bvalid_o/rvalid_o not 0 in reset");
                #1 rst_n = 1'b1;
                regs = '{default: '0};
                wbase = nw;
                nbs = nw;
                nb = nw;
                rbase = nr;
                nrs = nr;
                nrb = nr;
                w_pres = 0;
                r_pres = 0;
                b_hold = 0;
                r_hold = 0;
                base_edge = edge_n;
            end else begin
                drive_write(drain);
                drive_read(drain);
            end
            #1;
            aw_hs = awvalid && awready === 1'b1;
            w_hs = wvalid && wready === 1'b1;
            b_hs = b_hold && bvalid === 1'b1 && bready;
            ar_hs = arvalid && arready === 1'b1;
            r_hs = r_hold && rvalid === 1'b1 && rready;
            @(posedge clk) edge_n++;
            if (w_pres) begin
                if (awvalid && w_aw_first[nw-1] < 0) w_aw_first[nw-1] = edge_n;
                if (wvalid && w_w_first[nw-1] < 0) w_w_first[nw-1] = edge_n;
                if (aw_hs) w_aw_acc[nw-1] = 1;
                if (w_hs) w_w_acc[nw-1] = 1;
                if (w_aw_acc[nw-1] && w_w_acc[nw-1]) w_pres = 0;
            end
            if (b_hs) begin
                a = w_addr[nb];
                if (a < 8'h0C)
                    for (int b = 0; b < 4; b++)
                        if (w_strb[nb][b]) regs[a[3:2]][8*b +: 8] = w_data[nb][8*b +: 8];
                w_hs_edge[nb] = edge_n;
                nb++;
                b_hold = 0;
            end
            if (r_pres) begin
                if (arvalid && r_first[nr-1] < 0) r_first[nr-1] = edge_n;
                if (ar_hs) begin
                    r_acc[nr-1] = 1;
                    r_pres = 0;
                end
            end
            if (r_hs) begin
                r_hs_edge[nrb] = edge_n;
                nrb++;
                r_hold = 0;
            end
        end
        if (nb != nw || nrb != nr || w_pres || r_pres)
            fail($sformatf("traffic did not drain: %0d of %0d writes, %0d of %0d reads answered",
                           nb, nw, nrb, nr));
        if (!did_reset || nw < 2000 || nr < 2000 || num_slverr < 500 || num_id_wr < 200 ||
            num_partial < 300)
            fail($sformatf("too little traffic: %0d writes, %0d reads, %0d slverr, %0d id, %0d partial, reset %0d", nw, nr, num_slverr, num_id_wr, num_partial,
                           did_reset));
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d errors, first at %s", errors, first);
        $finish;
    end
endmodule
