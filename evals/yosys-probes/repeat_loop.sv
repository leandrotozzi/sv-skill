// expect: OK
module repeat_loop (input logic [7:0] a, output logic [7:0] y, output logic ok);
  always_comb begin
    y = a;
    repeat (3) y = y + 8'd1;
  end
  assign ok = (y == a + 8'd3);
endmodule
