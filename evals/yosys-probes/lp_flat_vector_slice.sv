// expect: OK
module lp_flat_vector_slice (input logic [1:0] i, output logic [7:0] y, output logic ok);
  localparam logic [31:0] T = {8'h44, 8'h33, 8'h22, 8'h11};
  assign y = T[i*8 +: 8];
  assign ok = (y == ((i == 0) ? 8'h11 : (i == 1) ? 8'h22 : (i == 2) ? 8'h33 : 8'h44));
endmodule
