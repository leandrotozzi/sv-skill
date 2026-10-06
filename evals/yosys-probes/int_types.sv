// expect: OK
module int_types (input logic [7:0] a, output logic [31:0] y, output logic ok);
  int i; byte b; shortint s; bit [7:0] bb; int unsigned u;
  always_comb begin b = a; s = b; i = s; bb = a; u = bb; end
  assign y = i;
  assign ok = (y == {{24{a[7]}}, a}) && (u == {24'd0, a});
endmodule
