// expect: OK
module var_decl_init_always (input logic [7:0] a, output logic [7:0] y, output logic ok);
  always_comb begin
    logic [7:0] t;
    t = a;
    y = t + 8'd1;
  end
  assign ok = (y == a + 8'd1);
endmodule
