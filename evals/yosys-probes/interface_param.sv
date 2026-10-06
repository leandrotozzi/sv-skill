// expect: WARN
interface pbus_if #(parameter int W = 8);
  logic [W-1:0] data;
endinterface
module interface_param (input logic [3:0] a, output logic [3:0] y, output logic ok);
  pbus_if #(.W(4)) b ();
  assign b.data = a;
  assign y = b.data;
  assign ok = (y == a);
endmodule
