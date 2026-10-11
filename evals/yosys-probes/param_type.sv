// expect: ERROR
// slang: OK
module param_type_sub #(parameter type T = logic [7:0]) (input T a, output T y);
  assign y = ~a;
endmodule
module param_type (input logic [3:0] a, output logic [3:0] y, output logic ok);
  param_type_sub #(.T(logic [3:0])) u_sub (.a(a), .y(y));
  assign ok = (y == ~a);
endmodule
