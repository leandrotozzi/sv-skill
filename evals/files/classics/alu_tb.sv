// Grader harness for eval 114: drives alu_req_t from the design's own alu_pkg
// and checks every rsp_o one cycle after its request against a model here.
module alu_tb;
    import alu_pkg::*;

    logic        clk = 1'b0;
    logic        rst_n = 1'b0;
    logic        valid_in = 1'b0;
    alu_req_t    req;
    logic        valid_out;
    alu_rsp_t    rsp;
    logic        exp_valid = 1'b0;
    logic [31:0] exp_result;
    int          errors = 0;
    int          cycle = 0;
    int          checked = 0;
    string       first = "";

    alu u_dut (
        .clk_i(clk), .rst_ni(rst_n), .valid_i(valid_in), .req_i(req), .valid_o(valid_out),
        .rsp_o(rsp)
    );

    always #5 clk = ~clk;

    function automatic logic [31:0] model(alu_req_t q);
        case (q.op)
            OpAdd: return q.a + q.b;
            OpSub: return q.a - q.b;
            OpAnd: return q.a & q.b;
            OpOr:  return q.a | q.b;
            OpXor: return q.a ^ q.b;
            OpSll: return q.a << q.b[4:0];
            OpSrl: return q.a >> q.b[4:0];
            default: return 32'($signed(q.a) >>> q.b[4:0]);
        endcase
    endfunction

    task automatic fail(string msg);
        if (errors == 0) first = $sformatf("cycle %0d: %s", cycle, msg);
        errors++;
    endtask

    task automatic step(input logic v, input alu_op_e op, input logic [31:0] a, b);
        @(negedge clk);
        cycle++;
        if (valid_out !== exp_valid) fail($sformatf("valid_o=%b, expected %b", valid_out, exp_valid));
        else if (exp_valid) begin
            checked++;
            if (rsp.result !== exp_result || rsp.zero !== (exp_result == 0))
                fail($sformatf("result=%h zero=%b, expected %h", rsp.result, rsp.zero, exp_result));
        end
        valid_in = v;
        req.op = op;
        req.a = a;
        req.b = b;
        exp_valid = rst_n && v;
        exp_result = model(req);
    endtask

    initial begin
        req = '0;
        #17 rst_n = 1'b1;
        step(0, OpAdd, '0, '0);
        for (int op = 0; op < 8; op++) begin
            step(1, alu_op_e'(op), 32'h8000_0001, 32'd1);
            step(1, alu_op_e'(op), 32'hFFFF_FFFF, 32'd31);
            step(1, alu_op_e'(op), 32'h0000_0005, 32'h0000_0005);  // zero for sub/xor
            step(1, alu_op_e'(op), 32'h8765_4321, 32'hFFFF_FFE4);  // shift by 4 (b[4:0])
            step(0, alu_op_e'(op), $urandom, $urandom);
        end
        for (int i = 0; i < 20000; i++) begin
            logic [31:0] a, b;
            a = $urandom;
            b = ($urandom_range(3) == 0) ? a : $urandom;
            step(1'($urandom_range(5) != 0), alu_op_e'($urandom_range(7)), a, b);
        end
        step(0, OpAdd, '0, '0);
        if (errors == 0 && checked > 15000) $display("EQUIV PASS");
        else $display("EQUIV FAIL: %0d errors (%0d checked), first at %s", errors, checked, first);
        $finish;
    end
endmodule
