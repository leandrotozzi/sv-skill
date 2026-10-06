// expect: OK
module const_var (input logic [7:0] a, output logic [7:0] y, output logic ok);
  always_comb begin
    automatic logic [7:0] k;
    k = 8'd5;
    y = a + k;
  end
  assign ok = (y == a + 8'd5);
endmodule
