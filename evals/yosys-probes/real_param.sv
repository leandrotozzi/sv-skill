// expect: ERROR
module real_param #(parameter real Ratio = 2.5) (output logic [7:0] y, output logic ok);
  localparam int N = int'(Ratio * 4.0);
  assign y = 8'(N);
  assign ok = (y == 8'd10);
endmodule
