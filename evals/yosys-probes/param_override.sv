// expect: OK
module param_override_sub #(parameter int W = 2) (output logic [7:0] y);
  assign y = 8'(W);
endmodule
module param_override (output logic [7:0] y, output logic ok);
  param_override_sub #(.W(7)) u_sub (.y(y));
  assign ok = (y == 8'd7);
endmodule
