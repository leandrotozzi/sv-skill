// expect: ERROR
module param_packed2d #(parameter logic [1:0][7:0] P = 16'h2211) (input logic i, output logic [7:0] y, output logic ok);
  assign y = P[i];
  assign ok = (y == (i ? 8'h22 : 8'h11));
endmodule
