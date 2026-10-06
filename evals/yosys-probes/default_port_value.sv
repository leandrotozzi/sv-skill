// expect: OK
module default_port_value_sub (input logic [7:0] a, input logic [7:0] b = 8'd5, output logic [7:0] y);
  assign y = a + b;
endmodule
module default_port_value (input logic [7:0] a, output logic [7:0] y, output logic ok);
  default_port_value_sub u_sub (.a(a), .y(y));
  assign ok = (y == a + 8'd5);
endmodule
