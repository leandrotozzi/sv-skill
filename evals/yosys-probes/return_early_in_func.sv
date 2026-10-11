// expect: ERROR
// slang: OK
module return_early_in_func (input logic [7:0] a, output logic [7:0] y, output logic ok);
  function automatic logic [7:0] f(logic [7:0] x);
    if (x[0]) return 8'd0;
    return x;
  endfunction
  assign y = f(a);
  assign ok = (y == (a[0] ? 8'd0 : a));
endmodule
