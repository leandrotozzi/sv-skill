// expect: WARN
module unpacked_array_pattern (input logic [7:0] a, input logic [7:0] b, input logic i, output logic [7:0] y, output logic ok);
  logic [7:0] arr [2];
  assign arr = '{a, b};
  assign y = arr[i];
  assign ok = (y == (i ? b : a));
endmodule
