// Reference package for eval 114 (only used to validate alu_tb).
package alu_pkg;
    typedef enum logic [2:0] {
        OpAdd = 3'd0, OpSub = 3'd1, OpAnd = 3'd2, OpOr = 3'd3,
        OpXor = 3'd4, OpSll = 3'd5, OpSrl = 3'd6, OpSra = 3'd7
    } alu_op_e;
    typedef struct packed {
        alu_op_e     op;
        logic [31:0] a;
        logic [31:0] b;
    } alu_req_t;
    typedef struct packed {
        logic [31:0] result;
        logic        zero;
    } alu_rsp_t;
endpackage
