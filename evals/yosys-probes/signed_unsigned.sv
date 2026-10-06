// expect: OK
module signed_unsigned (input logic [7:0] a, output logic [8:0] y, output logic [8:0] z, output logic ok);
  assign y = $signed(a);
  assign z = $unsigned($signed(a));
  assign ok = (y == {a[7], a}) && (z == {1'b0, a});
endmodule
