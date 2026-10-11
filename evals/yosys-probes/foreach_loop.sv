// expect: ERROR
// slang: OK
module foreach_loop (input logic [7:0] a, output logic [7:0] y, output logic ok);
  always_comb begin
    y = '0;
    foreach (a[i]) y[i] = ~a[i];
  end
  assign ok = (y == ~a);
endmodule
