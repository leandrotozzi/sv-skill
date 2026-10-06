// Grader harness for eval 124: self-checking, at Width 16 and Width 5. The
// latency is measured on the first set (at most 6 cycles) and must then stay
// fixed: valid_o on every cycle must equal valid_i that many cycles earlier,
// and each valid data_o must be the ascending permutation of that input set.
// Stimulus: all 256 sets of keys in {0, 1} and in {0, max} (0-1 principle),
// sorted, reverse, all-equal and duplicate sets, then random sets (full range,
// narrow ranges with many duplicates, extremes) under full throughput, random
// gaps and sparse valids, with one asynchronous reset that discards the sets
// in flight. data_o is ignored while valid_o is 0.
module sort8_chk #(
    parameter int W = 16
);
    localparam int N = 16000;  // stimulus cycles
    localparam logic [W-1:0] Max = '1;

    logic           clk = 1'b0;
    logic           rst_n = 1'b0;
    logic           valid = 1'b0;
    logic [8*W-1:0] data = '0;
    logic           valid_o;
    logic [8*W-1:0] data_o;

    sort8 #(.Width(W)) u_dut (
        .clk_i(clk), .rst_ni(rst_n), .valid_i(valid), .data_i(data), .valid_o(valid_o),
        .data_o(data_o)
    );

    always #5 clk = ~clk;

    int    errors = 0;
    string first = "";
    bit    done = 0;
    int    cycle = 0;            // posedges seen
    bit    vin [N + 64];         // valid_i sampled at posedge c
    logic [8*W-1:0] din [N + 64];
    int    first_in = -1;        // posedge of the first valid input
    int    lat = -1;             // measured delay, posedges, from input edge to output
    int    num_out = 0;

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("W=%0d cycle %0d: %s", W, cycle, msg);
        errors++;
    endtask

    function automatic logic [8*W-1:0] sorted(logic [8*W-1:0] s);
        logic [W-1:0] k [8];
        logic [8*W-1:0] r;
        for (int i = 0; i < 8; i++) k[i] = s[i*W +: W];
        for (int i = 1; i < 8; i++)
            for (int j = i; j > 0 && k[j-1] > k[j]; j--) begin
                automatic logic [W-1:0] t = k[j];
                k[j] = k[j-1];
                k[j-1] = t;
            end
        for (int i = 0; i < 8; i++) r[i*W +: W] = k[i];
        return r;
    endfunction

    function automatic logic [W-1:0] rkey(int mode);
        case (mode)
            0: return W'($urandom);
            1: return W'($urandom_range(3));                           // many duplicates
            2: return Max - W'($urandom_range(3));
            3: begin
                automatic logic [W-1:0] e [6] = '{'0, Max, W'(1), Max - 1, Max >> 1, ~(Max >> 1)};
                return e[$urandom_range(5)];
            end
            default: return W'($urandom) >> $urandom_range(W - 1);
        endcase
    endfunction

    // Directed sets, sent back to back first.
    logic [8*W-1:0] directed [$];
    initial begin
        logic [8*W-1:0] s;
        for (int p = 0; p < 256; p++) begin
            for (int i = 0; i < 8; i++) s[i*W +: W] = p[i] ? W'(1) : '0;
            directed.push_back(s);
            for (int i = 0; i < 8; i++) s[i*W +: W] = p[i] ? Max : '0;
            directed.push_back(s);
        end
        for (int i = 0; i < 8; i++) s[i*W +: W] = W'(i);
        directed.push_back(s);
        for (int i = 0; i < 8; i++) s[i*W +: W] = W'(7 - i);
        directed.push_back(s);
        for (int i = 0; i < 8; i++) s[i*W +: W] = Max - W'(i);
        directed.push_back(s);
        for (int i = 0; i < 8; i++) s[i*W +: W] = Max - W'(7 - i);
        directed.push_back(s);
        directed.push_back('0);
        directed.push_back('1);
        directed.push_back({8{Max >> 1}});
        directed.push_back({8{~(Max >> 1)}});
        for (int i = 0; i < 8; i++) s[i*W +: W] = (i % 2) ? W'(3) : W'(2);
        directed.push_back(s);
        for (int i = 0; i < 8; i++) s[i*W +: W] = (i < 4) ? Max : W'(1);
        directed.push_back(s);
    end

    // Outputs settled after posedge `cycle` (we are at a negedge).
    task automatic observe();
        if ($isunknown(valid_o)) begin
            fail("valid_o unknown");
            return;
        end
        if (lat < 0) begin
            if (valid_o) begin
                if (first_in < 0) fail("valid_o before any valid input");
                else begin
                    lat = cycle - first_in;
                    if (lat > 5) fail($sformatf("latency %0d cycles, limit 6", lat + 1));
                end
            end else if (first_in >= 0 && cycle - first_in > 5) begin
                fail("no valid_o within 6 cycles of the first valid input");
                lat = 1000;
            end
        end
        if (lat >= 0 && lat <= cycle) begin
            automatic bit ev = vin[cycle - lat];
            if (valid_o !== ev)
                fail($sformatf("valid_o=%b, expected %b (latency %0d)", valid_o, ev, lat + 1));
            else if (ev) begin
                automatic logic [8*W-1:0] exp = sorted(din[cycle - lat]);
                num_out++;
                if (data_o !== exp)
                    fail($sformatf("input %h gave %h, expected %h", din[cycle - lat], data_o, exp));
            end
        end
    endtask

    initial begin
        int mode = 0;
        bit did_reset = 0;
        #17 rst_n = 1'b1;
        for (int i = 0; i < N + 12; i++) begin
            int phase;
            @(negedge clk);
            observe();
            // phase 0: valid every cycle; 1: random gaps; 2: sparse.
            phase = (i < 1000) ? 0 : (i / 400) % 3;
            if (i >= N) valid = 1'b0;
            else if (phase == 0) valid = 1'b1;
            else if (phase == 1) valid = $urandom_range(1);
            else valid = ($urandom_range(7) == 0);
            if (i % 37 == 0) mode = $urandom_range(4);
            if (valid) begin
                if (directed.size() != 0) data = directed.pop_front();
                else for (int k = 0; k < 8; k++) data[k*W +: W] = rkey(mode);
            end else data = {8{W'($urandom)}};
            // One asynchronous reset in the middle of a full-throughput burst.
            if (!did_reset && i == 12000) begin
                did_reset = 1;
                valid = 1'b0;
                #1 rst_n = 1'b0;
                #1 if (valid_o !== 1'b0) fail("valid_o not cleared by reset");
                foreach (vin[c]) vin[c] = 0;
            end else if (!rst_n) begin
                #1 rst_n = 1'b1;
            end
            @(posedge clk);
            cycle++;
            vin[cycle] = valid && rst_n;
            din[cycle] = data;
            if (valid && rst_n && first_in < 0) first_in = cycle;
        end
        if (num_out < 6000) fail($sformatf("only %0d sets came out", num_out));
        done = 1;
    end
endmodule

module sort8_tb;
    sort8_chk #(.W(16)) u_w16 ();
    sort8_chk #(.W(5)) u_w5 ();

    initial begin
        #2000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    initial begin
        wait (u_w16.done && u_w5.done);
        if (u_w16.errors + u_w5.errors == 0) $display("EQUIV PASS");
        else
            $display("EQUIV FAIL: %0d errors, first at %s", u_w16.errors + u_w5.errors,
                     u_w16.errors ? u_w16.first : u_w5.first);
        $finish;
    end
endmodule
