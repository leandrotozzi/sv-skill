// expect: OK
module typedef_in_module (input logic [7:0] a, output logic [7:0] y, output logic ok);
  typedef logic [7:0] byte_t;
  byte_t t;
  assign t = a;
  assign y = t;
  assign ok = (y == a);
endmodule
