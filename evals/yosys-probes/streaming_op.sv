// expect: ERROR
module streaming_op (input logic [7:0] a, output logic [7:0] y, output logic ok);
  assign y = {<<{a}};
  assign ok = (y == {a[0],a[1],a[2],a[3],a[4],a[5],a[6],a[7]});
endmodule
