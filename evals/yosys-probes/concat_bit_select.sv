// expect: ERROR
module concat_bit_select (input logic [3:0] a, input logic [3:0] b, output logic y, output logic ok);
  assign y = {a, b}[5];
  assign ok = (y == a[1]);
endmodule
