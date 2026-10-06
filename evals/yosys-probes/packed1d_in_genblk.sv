// expect: OK
module packed1d_in_genblk (input logic [31:0] a, output logic [7:0] y, output logic ok);
  for (genvar g = 0; g < 1; g++) begin : gen_s
    logic [31:0] v;
    assign v = a;
    assign y = v[15:8];
  end
  assign ok = (y == a[15:8]);
endmodule
