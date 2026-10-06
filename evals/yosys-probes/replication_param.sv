// expect: OK
module replication_param #(parameter int N = 3) (input logic [1:0] a, output logic [5:0] y, output logic ok);
  assign y = {N{a}};
  assign ok = (y == {a, a, a});
endmodule
