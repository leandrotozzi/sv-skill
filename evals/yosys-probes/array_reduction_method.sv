// expect: ERROR
module array_reduction_method (input logic [7:0] a, output logic [3:0] y);
  logic [3:0] s [2];
  assign s[0] = a[3:0];
  assign s[1] = a[7:4];
  assign y = s.sum();
endmodule
