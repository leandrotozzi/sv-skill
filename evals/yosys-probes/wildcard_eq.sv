// expect: ERROR
// slang: OK
module wildcard_eq (input logic [3:0] a, output logic y, output logic ok);
  assign y = (a ==? 4'b1?0?);
  assign ok = (y == (a[3] && !a[1]));
endmodule
