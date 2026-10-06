// expect: ERROR
module void_cast (input logic [7:0] a, output logic [7:0] y, output logic ok);
  function automatic logic [7:0] f(logic [7:0] x); f = x; endfunction
  always_comb begin void'(f(a)); y = a; end
  assign ok = (y == a);
endmodule
