// expect: OK
module packed2d_module (input logic [31:0] a, input logic [1:0] i, output logic [7:0] y, output logic ok);
  logic [3:0][7:0] v;
  assign v = a;
  assign y = v[i];
  assign ok = (y == a[i*8 +: 8]);
endmodule
