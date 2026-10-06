// expect: ERROR
module return_in_func (input logic [7:0] a, output logic [7:0] y, output logic ok);
  function automatic logic [7:0] f(logic [7:0] x);
    return x + 8'd3;
  endfunction
  assign y = f(a);
  assign ok = (y == a + 8'd3);
endmodule
