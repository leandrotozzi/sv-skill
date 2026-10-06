// expect: OK
module power_op (output logic [15:0] y, output logic ok);
  localparam int N = 2 ** 10;
  assign y = 16'(N);
  assign ok = (y == 16'd1024);
endmodule
