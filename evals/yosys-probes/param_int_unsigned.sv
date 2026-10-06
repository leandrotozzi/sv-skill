// expect: OK
module param_int_unsigned #(parameter int unsigned N = 5, parameter bit En = 1'b1) (output logic [7:0] y, output logic ok);
  assign y = En ? 8'(N) : 8'd0;
  assign ok = (y == 8'd5);
endmodule
