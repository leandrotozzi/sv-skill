// expect: ERROR
module let_decl (input logic [7:0] a, input logic [7:0] b, output logic [7:0] y, output logic ok);
  let mx(x, z) = (x > z) ? x : z;
  assign y = mx(a, b);
  assign ok = (y == ((a > b) ? a : b));
endmodule
