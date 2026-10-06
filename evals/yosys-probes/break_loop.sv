// expect: ERROR
module break_loop (input logic [7:0] a, output logic [3:0] y, output logic ok);
  always_comb begin
    y = 4'd8;
    for (int i = 0; i < 8; i++) if (a[i]) begin y = 4'(i); break; end
  end
  assign ok = 1'b1;
endmodule
