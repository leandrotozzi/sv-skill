// expect: OK
module packed1d_in_begin (input logic [31:0] a, output logic [7:0] y, output logic ok);
  always_comb begin : blk
    logic [31:0] v;
    v = a;
    y = v[15:8];
  end
  assign ok = (y == a[15:8]);
endmodule
