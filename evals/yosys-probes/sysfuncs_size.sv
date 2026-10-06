// expect: OK
module sysfuncs_size (input logic [11:0] a, output logic [31:0] y, output logic ok);
  logic [3:0][2:0] v;
  assign v = a;
  localparam int B = $bits(v);
  localparam int C = $clog2(12);
  localparam int S = $size(v);
  localparam int H = $high(v);
  localparam int L = $low(v);
  assign y = 32'(B * 1000 + C * 100 + S * 10 + H + L);
  assign ok = (y == 32'(12 * 1000 + 4 * 100 + 4 * 10 + 3 + 0));
endmodule
