// expect: OK
module sized_cast #(parameter int W = 4) (input logic [7:0] a, output logic [3:0] y, output logic ok);
  assign y = W'(a);
  assign ok = (y == a[3:0]);
endmodule
