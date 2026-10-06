// expect: OK
module real_param_rtoi #(parameter real Ratio = 2.5) (output logic [7:0] y, output logic ok);
  localparam int N = $rtoi(Ratio * 4.0);
  assign y = 8'(N);
  assign ok = (y == 8'd10);
endmodule
