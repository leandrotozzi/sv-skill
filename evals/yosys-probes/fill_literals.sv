// expect: OK
module fill_literals (input logic s, output logic [11:0] y, output logic ok);
  assign y = s ? '1 : '0;
  assign ok = (y == {12{s}});
endmodule
