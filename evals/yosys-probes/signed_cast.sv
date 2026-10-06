// expect: OK
module signed_cast (input logic [7:0] a, output logic [8:0] y, output logic ok);
  assign y = signed'(a);
  assign ok = (y == {a[7], a});
endmodule
