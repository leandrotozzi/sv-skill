// expect: ERROR
// slang: OK
module lp_unpacked_array (input logic [1:0] i, output logic [7:0] y, output logic ok);
  localparam logic [7:0] T [4] = '{8'h11, 8'h22, 8'h33, 8'h44};
  assign y = T[i];
  assign ok = (y == ((i == 0) ? 8'h11 : (i == 1) ? 8'h22 : (i == 2) ? 8'h33 : 8'h44));
endmodule
