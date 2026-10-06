// expect: WRONG
// note: T[i] on a typedef with two packed dimensions is read as a 1-bit select of the flat vector.
module lp_packed2d_typedef (input logic [1:0] i, output logic [7:0] y, output logic ok);
  typedef logic [3:0][7:0] tbl_t;
  localparam tbl_t T = {8'h44, 8'h33, 8'h22, 8'h11};
  assign y = T[i];
  assign ok = (y == ((i == 0) ? 8'h11 : (i == 1) ? 8'h22 : (i == 2) ? 8'h33 : 8'h44));
endmodule
