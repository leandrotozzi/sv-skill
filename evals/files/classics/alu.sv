// Reference ALU for eval 114 (only used to validate alu_tb).
module alu
    import alu_pkg::*;
(
    input  logic     clk_i,
    input  logic     rst_ni,
    input  logic     valid_i,
    input  alu_req_t req_i,
    output logic     valid_o,
    output alu_rsp_t rsp_o
);
    logic [31:0] r;

    always_comb begin
        case (req_i.op)
            OpAdd:   r = req_i.a + req_i.b;
            OpSub:   r = req_i.a - req_i.b;
            OpAnd:   r = req_i.a & req_i.b;
            OpOr:    r = req_i.a | req_i.b;
            OpXor:   r = req_i.a ^ req_i.b;
            OpSll:   r = req_i.a << req_i.b[4:0];
            OpSrl:   r = req_i.a >> req_i.b[4:0];
            default: r = 32'($signed(req_i.a) >>> req_i.b[4:0]);
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) valid_o <= 1'b0;
        else valid_o <= valid_i;
    end

    always_ff @(posedge clk_i) begin
        if (valid_i) rsp_o <= '{result: r, zero: r == 0};
    end
endmodule
