// expect: OK
module generate_case #(parameter int M = 1) (input logic [7:0] a, output logic [7:0] y, output logic ok);
  case (M)
    0: begin : gen_m0 assign y = a; end
    1: begin : gen_m1 assign y = ~a; end
    default: begin : gen_md assign y = '0; end
  endcase
  assign ok = (y == ~a);
endmodule
