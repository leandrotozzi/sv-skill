// expect: ERROR
// slang: OK
module automatic_init_always (input logic [7:0] a, output logic [7:0] y, output logic ok);
  always_comb begin
    automatic logic [7:0] t = a;
    y = t + 8'd1;
  end
  assign ok = (y == a + 8'd1);
endmodule
