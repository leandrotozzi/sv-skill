// Grader harness for eval 117: two fwft_fifo instances (Width 32 / Depth 512 and
// Width 8 / Depth 4) get random valid/ready traffic, long fills to full, drains,
// streaming with both sides held at 1, and an asynchronous reset mid-run. A model
// queue in the testbench checks, every cycle: count_o equals words accepted minus
// words that left; in_ready_o == (count_o < Depth); out_data_o is the oldest word
// whenever out_valid_o is 1; each word is shown no later than after edge n+3 (n the
// edge that accepted it) or the edge its predecessor left, whichever is later;
// out_valid_o never drops before its word leaves; and, with in_valid_i and
// out_ready_i held at 1, a word leaves on every cycle once the first one appears.
module fwft_fifo_tb_run #(
    parameter int W = 32,
    parameter int D = 512,
    parameter int Cycles = 20000
) (
    input logic clk
);
    localparam int CW = $clog2(D) + 1;

    logic          rst_n = 1'b0;
    logic          in_valid = 1'b0, out_ready = 1'b0;
    logic [W-1:0]  in_data = '0;
    logic          in_ready, out_valid;
    logic [W-1:0]  out_data;
    logic [CW-1:0] count;

    fwft_fifo #(.Width(W), .Depth(D)) u_dut (
        .clk_i(clk), .rst_ni(rst_n), .in_valid_i(in_valid), .in_ready_o(in_ready),
        .in_data_i(in_data), .out_valid_o(out_valid), .out_ready_i(out_ready),
        .out_data_o(out_data), .count_o(count)
    );

    int    errors = 0;
    string first = "";
    bit    done = 0;
    int    edges = 0;          // posedges seen
    int    num_out = 0, max_count = 0;

    logic [W-1:0] q_data [$];
    int           q_acc [$];   // edge that accepted each queued word
    int           head_since;  // edge on which q[0] became the oldest word
    bit           prev_valid = 0;
    bit           streaming = 0;  // in_valid and out_ready held at 1 from empty
    bit           stream_seen = 0;

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("W=%0d D=%0d edge %0d: %s", W, D, edges, msg);
        errors++;
    endtask

    // Checks on the outputs settled after the last edge (called at negedge).
    task automatic observe();
        if ($isunknown({in_ready, out_valid, count})) begin
            fail("in_ready_o/out_valid_o/count_o unknown");
            return;
        end
        if (count != q_data.size())
            fail($sformatf("count_o=%0d, expected %0d", count, q_data.size()));
        if (in_ready !== (q_data.size() < D))
            fail($sformatf("in_ready_o=%b with %0d words held", in_ready, q_data.size()));
        if (out_valid) begin
            if (q_data.size() == 0) fail("out_valid_o with no word held");
            else if (out_data !== q_data[0])
                fail($sformatf("out_data_o=%h, oldest word is %h", out_data, q_data[0]));
        end else if (q_data.size() != 0) begin
            int due = q_acc[0] + 3 > head_since ? q_acc[0] + 3 : head_since;
            if (edges >= due)
                fail($sformatf("oldest word (accepted on edge %0d) not shown by edge %0d",
                               q_acc[0], due));
            if (prev_valid) fail("out_valid_o dropped before its word left");
            if (streaming && stream_seen) fail("bubble while streaming with valid/ready at 1");
        end
        if (streaming && out_valid) stream_seen = 1;
        prev_valid = out_valid;
    endtask

    // One clock: drive inputs (we are at a negedge), take the handshakes just
    // before the edge, update the model on it, then check after it.
    task automatic step(bit iv, bit ordy);
        bit push, pop;
        in_valid  = iv;
        out_ready = ordy;
        in_data   = W'({$urandom, $urandom});
        #4;
        push = in_valid && in_ready === 1'b1;
        pop  = out_valid === 1'b1 && out_ready;
        if (pop && q_data.size() != 0 && out_data !== q_data[0])
            fail($sformatf("out_data_o=%h at the pop edge, oldest word is %h", out_data,
                           q_data[0]));
        @(posedge clk);
        edges++;
        if (pop && q_data.size() != 0) begin
            void'(q_data.pop_front());
            void'(q_acc.pop_front());
            head_since = edges;
            num_out++;
            prev_valid = 0;
        end
        if (push) begin
            if (q_data.size() == 0) head_since = edges;
            q_data.push_back(in_data);
            q_acc.push_back(edges);
        end
        if (q_data.size() > max_count) max_count = q_data.size();
        @(negedge clk);
        observe();
    endtask

    task automatic do_reset();
        #1 rst_n = 1'b0;
        #1 if (count !== '0 || out_valid !== 1'b0 || in_ready !== 1'b1)
            fail("reset did not empty the FIFO");
        #1 rst_n = 1'b1;
        in_valid  = 1'b0;
        out_ready = 1'b0;
        q_data.delete();
        q_acc.delete();
        prev_valid = 0;
    endtask

    initial begin
        int pv, pr;
        @(negedge clk);
        #2 rst_n = 1'b1;
        @(negedge clk);
        observe();
        // Fill to full, hold with in_valid high, then drain completely.
        repeat (D + 20) step(1, 0);
        repeat (20) step(1, $urandom % 2);  // at the full boundary
        repeat (40) step($urandom % 4 == 0, 1);
        repeat (D + 20) step(0, 1);
        // Stream from empty with both sides held at 1.
        streaming = 1;
        stream_seen = 0;
        repeat (300) step(1, 1);
        streaming = 0;
        repeat (D + 20) step(0, 1);
        // Single words into an empty FIFO, popped at once.
        repeat (40) begin
            step(1, 1);
            repeat ($urandom % 6) step(0, 1);
        end
        for (int i = 0; i < Cycles; i++) begin
            if (i % 200 == 0) begin
                // Phases: fill-heavy, drain-heavy, balanced, sparse.
                case ($urandom % 4)
                    0: begin pv = 9; pr = 3; end
                    1: begin pv = 3; pr = 9; end
                    2: begin pv = 7; pr = 7; end
                    default: begin pv = 2; pr = 2; end
                endcase
            end
            if (i == Cycles / 2) begin
                // Get some words in flight, then reset asynchronously.
                repeat (3) step(1, 0);
                step(1, 1);
                do_reset();
                @(posedge clk);
                edges++;
                @(negedge clk);
                observe();
            end
            step($urandom % 10 < pv, $urandom % 10 < pr);
        end
        done = 1;
    end
endmodule

module fwft_fifo_tb;
    logic clk = 1'b0;
    always #5 clk = ~clk;

    fwft_fifo_tb_run #(.W(32), .D(512), .Cycles(100000)) u_big (.clk(clk));
    fwft_fifo_tb_run #(.W(8), .D(4), .Cycles(100000)) u_small (.clk(clk));

    initial begin
        #50000000;
        $display("EQUIV FAIL: timeout");
        $finish;
    end

    initial begin
        wait (u_big.done && u_small.done);
        if (u_big.errors + u_small.errors != 0)
            $display("EQUIV FAIL: %0d errors, first at %s", u_big.errors + u_small.errors,
                     u_big.errors ? u_big.first : u_small.first);
        else if (u_big.max_count != 512 || u_small.max_count != 4)
            $display("EQUIV FAIL: 1 error, first at FIFO never held Depth words (max %0d / %0d)",
                     u_big.max_count, u_small.max_count);
        else
            $display("EQUIV PASS");
        $finish;
    end
endmodule
