// expect: ERROR
module lp_unpacked_param_array #(parameter logic [7:0] P [2] = '{8'h11, 8'h22}) (input logic i, output logic [7:0] y);
  assign y = P[i];
endmodule
