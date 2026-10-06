// expect: OK
module arith_shift (input logic signed [7:0] a, output logic signed [7:0] y, output logic ok);
  assign y = a >>> 2;
  assign ok = (y == {{2{a[7]}}, a[7:2]});
endmodule
