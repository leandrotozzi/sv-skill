// Grader harness for eval 128: the design under test at Channels/Width = 1/4
// and 4/8 runs against a cycle-exact behavioural model of the spec (counter
// 0..P, pending set taken at the wrap, a load in the wrap cycle included);
// pwm_o and sync_o must match on every cycle. Directed loads cover period 0,
// duty 0, duty == P, duty > P, several loads in one period and a load in the
// wrap cycle, then random loads and resets run; coverage counters make sure
// each case was really hit.
module pwm_bank_chk #(
    parameter int C = 4,
    parameter int W = 8
) (
    input logic        clk,
    input logic        rst_n,
    input logic        load,
    input logic [15:0] period,
    input logic [63:0] duty,
    input int          cycle
);
    logic [W-1:0]   dut_period;
    logic [C*W-1:0] dut_duty;
    logic [C-1:0]   pwm_dut, pwm_exp;
    logic           sync_dut, sync_exp;

    // Model state.
    logic [W-1:0]   m_cnt, m_per, m_pper;
    logic [W-1:0]   m_duty[C], m_pduty[C];
    logic           m_pend;

    int             errors = 0;
    string          first = "";
    int cov_wrap_load = 0, cov_multi = 0, cov_p0 = 0, cov_d0 = 0, cov_deq = 0, cov_dgt = 0;
    int cov_rst_pend = 0;

    always_comb begin
        dut_period = period[W-1:0];
        for (int c = 0; c < C; c++) dut_duty[c*W+:W] = duty[c*16+:W];
    end

    pwm_bank #(.Channels(C), .Width(W)) u_dut (
        .clk_i(clk), .rst_ni(rst_n), .load_i(load), .period_i(dut_period), .duty_i(dut_duty),
        .pwm_o(pwm_dut), .sync_o(sync_dut)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if (m_pend === 1'b1) cov_rst_pend++;
            m_cnt  <= '0;
            m_per  <= '0;
            m_pper <= '0;
            m_pend <= 1'b0;
            for (int c = 0; c < C; c++) begin
                m_duty[c]  <= '0;
                m_pduty[c] <= '0;
            end
        end else begin
            logic wrap;
            wrap = m_cnt == m_per;
            if (load && wrap) cov_wrap_load++;
            if (load && m_pend) cov_multi++;
            m_cnt <= wrap ? '0 : m_cnt + 1'b1;
            if (load) begin
                m_pper <= dut_period;
                for (int c = 0; c < C; c++) m_pduty[c] <= duty[c*16+:W];
            end
            if (wrap && (load || m_pend)) begin
                m_per <= load ? dut_period : m_pper;
                for (int c = 0; c < C; c++) m_duty[c] <= load ? duty[c*16+:W] : m_pduty[c];
            end
            m_pend <= wrap ? 1'b0 : (m_pend || load);
        end
    end

    always_comb begin
        for (int c = 0; c < C; c++) pwm_exp[c] = m_cnt < m_duty[c];
        sync_exp = m_cnt == '0;
    end

    always @(negedge clk) begin
        if (rst_n) begin
            if (m_per == '0) cov_p0++;
            if (m_duty[0] == '0) cov_d0++;
            if (m_duty[0] == m_per && m_per != '0) cov_deq++;
            if (m_duty[0] > m_per) cov_dgt++;
        end
        if (pwm_dut !== pwm_exp || sync_dut !== sync_exp) begin
            if (errors == 0)
                first = $sformatf(
                    "cycle %0d (Channels %0d, Width %0d, cnt %0d, P %0d): pwm_o exp=%b dut=%b sync_o exp=%b dut=%b",
                    cycle, C, W, m_cnt, m_per, pwm_exp, pwm_dut, sync_exp, sync_dut);
            errors++;
        end
    end
endmodule

module pwm_bank_tb;
    logic        clk = 1'b0;
    logic        rst_n = 1'b0;
    logic        load = 1'b0;
    logic [15:0] period = '0;
    logic [63:0] duty = '0;
    int          cycle = 0;

    pwm_bank_chk #(.C(1), .W(4)) u_c1w4 (.*);
    pwm_bank_chk #(.C(4), .W(8)) u_c4w8 (.*);

    always #5 clk = ~clk;

    // Inputs change at the negedge; the posedge that follows samples them.
    task automatic step(input logic l, input logic [15:0] p, input logic [63:0] d);
        @(negedge clk);
        cycle++;
        load = l;
        period = p;
        duty = d;
    endtask

    // Drive inputs at the current negedge (after to_wrap/to_cnt1).
    task automatic drive(input logic l, input logic [15:0] p, input logic [63:0] d);
        load = l;
        period = p;
        duty = d;
    endtask

    task automatic idle(int n);
        repeat (n) step(0, 16'hdead, {4{16'hbeef}});
    endtask

    // Duties packed at 16 bits per channel; each checker slices its Width.
    function automatic logic [63:0] d4(int a, int b, int c, int e);
        return {16'(e), 16'(c), 16'(b), 16'(a)};
    endfunction

    // Stop at the negedge before a wrap posedge (both models agree when
    // every loaded value fits in 4 bits).
    task automatic to_wrap();
        @(negedge clk);
        cycle++;
        load = 1'b0;
        while (u_c4w8.m_cnt != u_c4w8.m_per) begin
            @(negedge clk);
            cycle++;
        end
    endtask

    // Stop at the negedge before a posedge with counter 1 (period at least 2).
    task automatic to_cnt1();
        @(negedge clk);
        cycle++;
        load = 1'b0;
        while (u_c4w8.m_cnt != 1) begin
            @(negedge clk);
            cycle++;
        end
    endtask

    task automatic rand_vals(output logic [15:0] p, output logic [63:0] d);
        int pp;
        case ($urandom_range(9))
            0, 1, 2, 3: pp = $urandom_range(3);
            4, 5, 6, 7: pp = $urandom_range(15);
            default:    pp = $urandom_range(16'hffff);
        endcase
        p = 16'(pp);
        for (int c = 0; c < 4; c++) begin
            case ($urandom_range(5))
                0: d[c*16+:16] = 16'(0);
                1: d[c*16+:16] = 16'(pp);
                2: d[c*16+:16] = 16'(pp + 1);
                3: d[c*16+:16] = 16'(pp - 1);
                default: d[c*16+:16] = 16'($urandom);
            endcase
        end
    endtask

    initial begin
        #(10 * 200_000);
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    initial begin
        logic [15:0] p;
        logic [63:0] d;
        #17 rst_n = 1'b1;
        idle(3);  // period 0 after reset: every cycle wraps, outputs low, sync high
        // Load during period 0 (that cycle is a wrap): duty 0, < P, == P, > P.
        step(1, 3, d4(0, 2, 3, 4));
        idle(12);
        // Several loads within one period: only the last becomes active.
        step(1, 10, d4(5, 5, 5, 5));
        idle(5);  // still P = 3, wrap happens in here
        to_cnt1();
        drive(1, 9, d4(1, 2, 3, 4));
        step(1, 6, d4(6, 7, 0, 3));
        step(1, 5, d4(2, 5, 6, 0));
        idle(20);
        // A lone load in the wrap cycle takes effect at that wrap.
        to_wrap();
        drive(1, 2, d4(1, 2, 3, 0));
        idle(9);
        // Pending load followed by another one in the wrap cycle: the wrap one wins.
        to_cnt1();
        drive(1, 7, d4(7, 7, 7, 7));
        to_wrap();
        drive(1, 4, d4(4, 1, 5, 0));
        idle(12);
        // Period 0 again via a mid-period load, then a period-0 wrap load.
        to_cnt1();
        drive(1, 0, d4(1, 0, 2, 1));
        idle(6);
        step(1, 0, d4(0, 1, 1, 0));
        idle(3);
        step(1, 6, d4(3, 6, 7, 0));
        idle(10);
        // Reset mid-period with a load pending: the pending set is lost.
        to_cnt1();
        drive(1, 2, d4(1, 1, 1, 1));
        idle(1);
        #2 rst_n = 1'b0;
        idle(3);
        #2 rst_n = 1'b1;
        idle(8);
        // Random loads (a third aimed at the wrap cycle) and rare resets.
        for (int i = 0; i < 20000; i++) begin
            rand_vals(p, d);
            if ($urandom_range(2999) == 0) begin
                @(negedge clk);
                cycle++;
                load = 1'b0;
                #2 rst_n = 1'b0;
                idle(1);
                #2 rst_n = 1'b1;
            end else if ($urandom_range(29) == 0) begin
                to_wrap();
                drive(1, p, d);
            end else step(1'($urandom_range(7) == 0), p, d);
        end
        idle(3);
        begin
            int errors;
            string first;
            errors = u_c1w4.errors + u_c4w8.errors;
            first  = u_c1w4.errors != 0 ? u_c1w4.first : u_c4w8.first;
            if (errors == 0 && (u_c4w8.cov_wrap_load == 0 || u_c4w8.cov_multi == 0
                    || u_c4w8.cov_p0 == 0 || u_c4w8.cov_d0 == 0 || u_c4w8.cov_deq == 0
                    || u_c4w8.cov_dgt == 0 || u_c4w8.cov_rst_pend == 0
                    || u_c1w4.cov_wrap_load == 0 || u_c1w4.cov_dgt == 0)) begin
                errors = 1;
                first  = "harness coverage hole";
            end
            if (errors == 0) $display("EQUIV PASS");
            else $display("EQUIV FAIL: %0d mismatching cycles, first at %s", errors, first);
        end
        $finish;
    end
endmodule
