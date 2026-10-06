// expect: OK
module incr_ops (input logic [7:0] a, output logic [7:0] y, output logic ok);
  always_comb begin
    y = a;
    y++;
    y += 8'd2;
    y <<= 1;
    y -= 8'd1;
  end
  assign ok = (y == (((a + 8'd3) << 1) - 8'd1));
endmodule
