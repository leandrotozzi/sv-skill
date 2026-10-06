// expect: ERROR
module packed2d_in_begin (input logic [31:0] a, output logic [7:0] y, output logic ok);
  always_comb begin : blk
    logic [3:0][7:0] v;
    v = a;
    y = v[1] ^ v[2];
  end
  assign ok = (y == (a[15:8] ^ a[23:16]));
endmodule
