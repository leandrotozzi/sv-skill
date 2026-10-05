// Grader harness for eval 107: checks the CORDIC against $cos/$sin. Every
// accepted angle must come out exactly once, in order, with one fixed latency
// of at most 20 cycles, cos/sin within 8 LSB (Q2.14) of the exact value.
module cordic_tb;
    localparam int    Tol = 8;
    localparam int    MaxLat = 20;
    localparam int    HalfPi = 12867;  // floor(pi/2 * 2**13)
    localparam real   Pi = 3.14159265358979323846;

    logic        clk = 1'b0;
    logic        rst_n = 1'b0;
    logic        valid_in = 1'b0;
    logic [15:0] angle = '0;
    logic        valid_out;
    logic [15:0] cos_out, sin_out;

    cordic u_dut (
        .clk_i(clk), .rst_ni(rst_n), .valid_i(valid_in), .angle_i(angle),
        .valid_o(valid_out), .cos_o(cos_out), .sin_o(sin_out)
    );

    always #5 clk = ~clk;

    initial begin
        #2000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    typedef struct {
        logic signed [15:0] angle;
        int                 edge_no;
    } item_t;

    item_t queue_q[$];
    int    errors = 0;
    string first = "";
    int    cycle = 0;
    int    latency = -1;
    int    max_err = 0;
    int    num_out = 0;

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("cycle %0d: %s", cycle, msg);
        errors++;
    endtask

    function automatic int abs_i(int v);
        return v < 0 ? -v : v;
    endfunction

    task automatic observe();
        if ($isunknown(valid_out)) fail("valid_o unknown");
        else if (valid_out) begin
            if (queue_q.size() == 0) fail("valid_o without a matching input");
            else begin
                item_t it = queue_q.pop_front();
                real   a = real'(it.angle) / 8192.0;
                int    exp_c = $rtoi($floor($cos(a) * 16384.0 + 0.5));
                int    exp_s = $rtoi($floor($sin(a) * 16384.0 + 0.5));
                int    lat = cycle - it.edge_no + 1;  // valid_i cycle to valid_o cycle
                int    err;
                num_out++;
                if (latency < 0) latency = lat;
                if (lat != latency) fail($sformatf("latency %0d, earlier %0d", lat, latency));
                if (lat > MaxLat) fail($sformatf("latency %0d > %0d", lat, MaxLat));
                if ($isunknown({cos_out, sin_out})) fail("cos_o/sin_o unknown with valid_o");
                else begin
                    err = abs_i(int'($signed(cos_out)) - exp_c);
                    if (abs_i(int'($signed(sin_out)) - exp_s) > err)
                        err = abs_i(int'($signed(sin_out)) - exp_s);
                    if (err > max_err) max_err = err;
                    if (err > Tol)
                        fail($sformatf("angle %0d: cos=%0d sin=%0d, expected %0d %0d", it.angle,
                                       int'($signed(cos_out)), int'($signed(sin_out)), exp_c, exp_s));
                end
            end
        end
    endtask

    function automatic logic [15:0] pick_angle(int i);
        int k = $urandom % 10;
        if (i < 8) begin
            // Directed corners first.
            case (i)
                0: return 16'(0);
                1: return 16'(HalfPi);
                2: return 16'(-HalfPi);
                3: return 16'(1);
                4: return 16'(-1);
                5: return 16'(6434);   // pi/4
                6: return 16'(-6434);
                default: return 16'(4289);  // ~pi/6
            endcase
        end
        if (k == 0) return 16'(int'($urandom % 64) - 32);         // small angles
        if (k == 1) return 16'(($urandom % 2) ? HalfPi - int'($urandom % 8)
                                              : -HalfPi + int'($urandom % 8));
        return 16'(int'($urandom % (2 * HalfPi + 1)) - HalfPi);
    endfunction

    initial begin
        int sent = 0;
        bit did_reset = 0;
        #17 rst_n = 1'b1;
        for (int i = 0; i < 8000; i++) begin
            int phase;
            bit v;
            @(negedge clk);
            observe();
            phase = (i / 400) % 3;
            // phase 0: long back-to-back burst; 1: random bubbles; 2: sparse.
            v = (phase == 0) || (phase == 1 && $urandom % 2 == 0) || ($urandom % 8 == 0);
            valid_in = v;
            angle = v ? pick_angle(sent) : 16'($urandom);
            if (v) begin
                queue_q.push_back('{angle, cycle + 1});
                sent++;
            end
            // Asynchronous reset once, in the middle of a burst.
            if (!did_reset && i == 4410) begin
                did_reset = 1;
                valid_in = 1'b0;
                #2 rst_n = 1'b0;
                #1 if (valid_out !== 1'b0) fail("valid_o not cleared by reset");
                #4 rst_n = 1'b1;
                queue_q.delete();
            end
            @(posedge clk) cycle++;
        end
        repeat (MaxLat + 10) begin
            @(negedge clk);
            observe();
            valid_in = 1'b0;
            @(posedge clk) cycle++;
        end
        if (queue_q.size() != 0) fail($sformatf("%0d inputs never came out", queue_q.size()));
        $display("cordic: %0d results, latency %0d, max error %0d LSB", num_out, latency, max_err);
        if (errors == 0) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d errors, first at %s", errors, first);
        $finish;
    end
endmodule
