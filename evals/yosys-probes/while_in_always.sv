// expect: ERROR
module while_in_always (input logic [7:0] a, output logic [7:0] y, output logic ok);
  int i;
  always_comb begin
    y = '0; i = 0;
    while (i < 8) begin y[i] = a[i]; i = i + 1; end
  end
  assign ok = (y == a);
endmodule
