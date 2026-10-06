// expect: WRONG
// note: v[i] on a typedef with two packed dimensions is read as a 1-bit select: y = {7'b0, a[i]}.
module typedef_2d_var_index (input logic [31:0] a, input logic [1:0] i, output logic [7:0] y, output logic ok);
  typedef logic [3:0][7:0] tbl_t;
  tbl_t v;
  assign v = a;
  assign y = v[i];
  assign ok = (y == a[i*8 +: 8]);
endmodule
