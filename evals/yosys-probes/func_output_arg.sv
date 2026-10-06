// expect: OK
module func_output_arg (input logic [7:0] a, output logic [7:0] y, output logic ok);
  function automatic void f(input logic [7:0] x, output logic [7:0] o); o = x << 1; endfunction
  always_comb f(a, y);
  assign ok = (y == {a[6:0], 1'b0});
endmodule
