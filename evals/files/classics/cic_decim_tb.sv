// Grader harness for eval 127: checks cic_decim against an arithmetic model of
// the prompt (integrators and combs wrapping at OutWidth), at Stages 1/3/5 x
// Rate 2/8/64. Every Rate-th accepted input must give exactly one one-cycle
// valid_o pulse 1 to 4 cycles later (pulses may overlap in flight, so they are
// matched in order), with data_o equal to the model output and held until the
// next pulse. valid_i runs back to back, half the time and sparsely; inputs
// include held full-scale positive and negative runs; an asynchronous reset
// hits three times mid-stream. data_o before the first pulse is not checked.
module cic_decim_chk #(
    parameter int S = 3,
    parameter int R = 8,
    parameter int IW = 12,
    parameter int Cycles = 12000
) (
    output bit    finished,
    output int    errors,
    output string first
);
    localparam int OW = IW + S * $clog2(R);
    localparam logic [IW-1:0] Max = {1'b0, {(IW - 1) {1'b1}}};
    localparam logic [IW-1:0] Min = {1'b1, {(IW - 1) {1'b0}}};
    localparam int Limit = 4;
    localparam int SegLen = 64 * R / 2 + 300;  // long enough to settle at full scale

    logic          clk = 1'b0;
    logic          rst_n = 1'b0;
    logic          valid = 1'b0;
    logic [IW-1:0] data = '0;
    logic          valid_o;
    logic [OW-1:0] data_o;

    cic_decim #(.Stages(S), .Rate(R), .InWidth(IW)) u_dut (
        .clk_i(clk), .rst_ni(rst_n), .valid_i(valid), .data_i(data), .valid_o(valid_o),
        .data_o(data_o)
    );

    always #5 clk = ~clk;

    // Model state.
    logic [OW-1:0] integ[S];
    logic [OW-1:0] cprev[S];
    int            n_in;
    logic [OW-1:0] exp_q[$];   // expected outputs, oldest first
    int            edge_q[$];  // posedge that accepted the Rate-th input
    int            cycle = 0;
    int            num_out = 0;
    bit            have_held = 0;
    logic [OW-1:0] held;

    initial begin
        errors = 0;
        first = "";
        finished = 0;
    end

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("Stages=%0d Rate=%0d InWidth=%0d cycle %0d: %s", S, R,
                                           IW, cycle, msg);
        errors++;
    endtask

    task automatic model_reset();
        for (int s = 0; s < S; s++) begin
            integ[s] = '0;
            cprev[s] = '0;
        end
        n_in = 0;
        exp_q.delete();
        edge_q.delete();
        have_held = 0;
    endtask

    // Input x is accepted at posedge number edge_no.
    task automatic model_accept(logic [IW-1:0] x, int edge_no);
        logic [OW-1:0] v, t;
        v = OW'($signed(x));
        for (int s = 0; s < S; s++) begin
            integ[s] += v;
            v = integ[s];
        end
        n_in++;
        if (n_in % R == 0) begin
            for (int s = 0; s < S; s++) begin
                t = v - cprev[s];
                cprev[s] = v;
                v = t;
            end
            exp_q.push_back(v);
            edge_q.push_back(edge_no);
        end
    endtask

    task automatic observe();
        if ($isunknown(valid_o)) fail("valid_o unknown");
        if (valid_o === 1'b1) begin
            if (exp_q.size() == 0) fail("valid_o with no output due (extra or wide pulse)");
            else begin
                logic [OW-1:0] e;
                int            lat;
                e   = exp_q.pop_front();
                lat = cycle + 1 - edge_q.pop_front();  // 1: registered right at that edge
                if (lat < 1 || lat > Limit) fail($sformatf("valid_o %0d cycles after input", lat));
                if (data_o !== e)
                    fail($sformatf("output %0d gave %0d, expected %0d", num_out, $signed(data_o),
                                   $signed(e)));
            end
            held = data_o;
            have_held = 1;
            num_out++;
        end else begin
            if (have_held && data_o !== held)
                fail($sformatf("data_o changed between pulses: %0d, held %0d", $signed(data_o),
                               $signed(held)));
            if (edge_q.size() != 0 && cycle + 1 - edge_q[0] >= Limit) begin
                fail($sformatf("no valid_o within %0d cycles of the Rate-th input", Limit));
                void'(exp_q.pop_front());
                void'(edge_q.pop_front());
            end
        end
    endtask

    initial begin
        int vmode, dmode;
        bit go;
        bit alt = 0;
        model_reset();
        #17 rst_n = 1'b1;
        for (int i = 0; i < Cycles; i++) begin
            int seg;
            @(negedge clk);
            observe();
            seg = i / SegLen;
            // A new mode per segment. The first three hold Max, Min and Max/Min
            // alternating, back to back, so the output reaches full scale.
            if (i % SegLen == 0) begin
                vmode = seg < 3 ? 0 : $urandom % 3;  // 0 back to back, 1 half, 2 sparse
                dmode = seg < 3 ? seg : $urandom % 5;
            end
            go = vmode == 0 || (vmode == 1 && $urandom % 2 == 0) || ($urandom % 9 == 0);
            // Asynchronous reset mid-stream, three times, not on a decimation boundary.
            if (i == Cycles / 4 + 1 || i == Cycles / 2 + 5 || i == 3 * Cycles / 4 + 2) begin
                valid = 1'b0;
                #1 rst_n = 1'b0;
                #1 if (valid_o !== 1'b0) fail("valid_o not cleared by reset");
                #1 if (valid_o !== 1'b0) fail("valid_o not held low in reset");
                #1 rst_n = 1'b1;
                model_reset();
                go = 0;
            end
            valid = go;
            case (dmode)
                0: data = Max;
                1: data = Min;
                2: data = alt ? Max : Min;
                3: data = IW'($signed(IW'($urandom)) >>> ($urandom % IW));
                default: data = IW'($urandom);
            endcase
            if (go) begin
                alt = !alt;
                model_accept(data, cycle + 1);
            end
            @(posedge clk) cycle++;
        end
        repeat (Limit + 2) begin
            @(negedge clk);
            observe();
            valid = 1'b0;
            @(posedge clk) cycle++;
        end
        if (exp_q.size() != 0) fail("outputs still due at the end");
        if (num_out < 40) fail($sformatf("too few outputs (%0d)", num_out));
        finished = 1;
    end
endmodule

module cic_decim_tb;
    bit    fin[9];
    int    err[9];
    string first[9];

    cic_decim_chk #(.S(1), .R(2), .IW(8)) u_s1r2 (fin[0], err[0], first[0]);
    cic_decim_chk #(.S(1), .R(8), .IW(16)) u_s1r8 (fin[1], err[1], first[1]);
    cic_decim_chk #(.S(1), .R(64), .IW(5), .Cycles(40000)) u_s1r64 (fin[2], err[2], first[2]);
    cic_decim_chk #(.S(3), .R(2), .IW(12)) u_s3r2 (fin[3], err[3], first[3]);
    cic_decim_chk #(.S(3), .R(8), .IW(12)) u_s3r8 (fin[4], err[4], first[4]);
    cic_decim_chk #(.S(3), .R(64), .IW(9), .Cycles(40000)) u_s3r64 (fin[5], err[5], first[5]);
    cic_decim_chk #(.S(5), .R(2), .IW(3)) u_s5r2 (fin[6], err[6], first[6]);
    cic_decim_chk #(.S(5), .R(8), .IW(16)) u_s5r8 (fin[7], err[7], first[7]);
    cic_decim_chk #(.S(5), .R(64), .IW(16), .Cycles(40000)) u_s5r64 (fin[8], err[8], first[8]);

    initial begin
        #5000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    initial begin
        int total = 0;
        string f = "";
        for (int k = 0; k < 9; k++) wait (fin[k]);
        for (int k = 0; k < 9; k++) begin
            if (err[k] != 0 && total == 0) f = first[k];
            total += err[k];
        end
        if (total == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d errors, first at %s", total, f);
        $finish;
    end
endmodule
