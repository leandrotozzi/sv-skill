// expect: WARN
// slang: OK
interface bus_if;
  logic [7:0] data;
  logic valid;
  modport src (output data, output valid);
  modport dst (input data, input valid);
endinterface
module interface_modport_src (bus_if.src b, input logic [7:0] a);
  assign b.data = a;
  assign b.valid = 1'b1;
endmodule
module interface_modport_dst (bus_if.dst b, output logic [7:0] y);
  assign y = b.valid ? b.data : 8'd0;
endmodule
module interface_modport (input logic [7:0] a, output logic [7:0] y, output logic ok);
  bus_if b ();
  interface_modport_src u_src (.b(b), .a(a));
  interface_modport_dst u_dst (.b(b), .y(y));
  assign ok = (y == a);
endmodule
