// expect: ERROR
module continue_loop (input logic [7:0] a, output logic [3:0] y, output logic ok);
  always_comb begin
    y = '0;
    for (int i = 0; i < 8; i++) begin if (!a[i]) continue; y = y + 4'd1; end
  end
  assign ok = 1'b1;
endmodule
