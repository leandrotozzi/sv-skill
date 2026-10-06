// expect: OK
module net_decl_assign (input logic [7:0] a, output logic [7:0] y, output logic ok);
  wire [7:0] t = a ^ 8'hff;
  assign y = t;
  assign ok = (y == ~a);
endmodule
