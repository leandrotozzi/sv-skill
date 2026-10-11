// expect: ERROR
// slang: WARN
module static_init_in_always (input logic [7:0] a, output logic [7:0] y, output logic ok);
  always_comb begin
    logic [7:0] t = 8'd1;
    y = a + t;
  end
  assign ok = (y == a + 8'd1);
endmodule
