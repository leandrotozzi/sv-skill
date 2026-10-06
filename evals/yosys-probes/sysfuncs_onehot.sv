// expect: OK
module sysfuncs_onehot (input logic [3:0] a, output logic [2:0] c, output logic o, output logic o0, output logic ok);
  assign c = $countones(a);
  assign o = $onehot(a);
  assign o0 = $onehot0(a);
  assign ok = (c == 3'(a[0] + a[1] + a[2] + a[3])) && (o == (c == 3'd1)) && (o0 == (c <= 3'd1));
endmodule
