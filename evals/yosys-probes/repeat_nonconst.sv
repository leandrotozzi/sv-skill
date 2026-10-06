// expect: ERROR
module repeat_nonconst (input logic [1:0] n, input logic [7:0] a, output logic [7:0] y, output logic ok);
  always_comb begin
    y = a;
    repeat (n) y = y + 8'd1;
  end
  assign ok = (y == a + 8'(n));
endmodule
