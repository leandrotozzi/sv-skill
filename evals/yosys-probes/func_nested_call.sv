// expect: OK
module func_nested_call (input logic [7:0] a, output logic [7:0] y, output logic ok);
  function automatic logic [7:0] g(logic [7:0] x); g = x ^ 8'h0f; endfunction
  function automatic logic [7:0] f(logic [7:0] x); f = g(x) + 8'd1; endfunction
  assign y = f(a);
  assign ok = (y == ((a ^ 8'h0f) + 8'd1));
endmodule
