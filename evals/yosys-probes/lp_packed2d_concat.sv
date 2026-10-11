// expect: ERROR
// slang: OK
module lp_packed2d_concat (input logic [1:0] i, output logic [7:0] y, output logic ok);
  localparam logic [3:0][7:0] T = {8'h44, 8'h33, 8'h22, 8'h11};
  assign y = T[i];
  assign ok = (y == ((i == 0) ? 8'h11 : (i == 1) ? 8'h22 : (i == 2) ? 8'h33 : 8'h44));
endmodule
