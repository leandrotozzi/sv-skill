// expect: ERROR
module lp_packed2d_const_index (output logic [7:0] y, output logic ok);
  localparam logic [3:0][7:0] T = {8'h44, 8'h33, 8'h22, 8'h11};
  assign y = T[2];
  assign ok = (y == 8'h33);
endmodule
