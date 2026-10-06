// expect: OK
module immediate_assert (input logic [7:0] a, output logic [7:0] y);
  assign y = a;
  always_comb assert (y == a);
endmodule
