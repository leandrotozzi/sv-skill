// expect: OK
module ifndef_synthesis_assert (input logic clk, input logic [7:0] a, output logic [7:0] y);
  assign y = a;
`ifndef SYNTHESIS
  property p_eq; @(posedge clk) y == a; endproperty
  assert property (p_eq);
`endif
endmodule
