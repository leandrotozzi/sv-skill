// expect: OK
module generate_hier_ref (input logic [7:0] a, output logic [7:0] y, output logic ok);
  for (genvar g = 0; g < 2; g++) begin : gen_s
    logic [7:0] t;
    assign t = a + 8'(g);
  end
  assign y = gen_s[1].t;
  assign ok = (y == a + 8'd1);
endmodule
