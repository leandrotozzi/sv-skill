// expect: WRONG
// note: parses (source reports call this the workaround), but v[i] is a 1-bit select, as typedef_2d_var_index.
module typedef_2d_in_genblk (input logic [31:0] a, input logic [1:0] i, output logic [7:0] y, output logic ok);
  typedef logic [3:0][7:0] tbl_t;
  for (genvar g = 0; g < 1; g++) begin : gen_s
    tbl_t v;
    assign v = a;
    assign y = v[i];
  end
  assign ok = (y == a[i*8 +: 8]);
endmodule
