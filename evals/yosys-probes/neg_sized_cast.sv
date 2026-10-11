// expect: ERROR
// slang: OK
module neg_sized_cast #(parameter int W = 8) (input logic [3:0] a, output logic [7:0] y, output logic ok);
  assign y = -W'(a);
  assign ok = (y == (8'd0 - {4'd0, a}));
endmodule
