// expect: OK
module found_flag_loop (input logic [7:0] a, output logic [3:0] y, output logic ok);
  logic found;
  always_comb begin
    y = 4'd8; found = 1'b0;
    for (int i = 0; i < 8; i++) if (a[i] && !found) begin y = 4'(i); found = 1'b1; end
  end
  assign ok = (a == 8'd0) ? (y == 4'd8) : (a[y[2:0]] && ((a & ((8'd1 << y[2:0]) - 8'd1)) == 8'd0));
endmodule
