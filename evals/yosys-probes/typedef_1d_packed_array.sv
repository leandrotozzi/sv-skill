// expect: OK
module typedef_1d_packed_array (input logic [31:0] a, input logic [1:0] i, output logic [7:0] y, output logic ok);
  typedef logic [7:0] b_t;
  b_t [3:0] v;
  assign v = a;
  assign y = v[i];
  assign ok = (y == a[i*8 +: 8]);
endmodule
