// expect: OK
module packed_array_port_sub (input logic [1:0][7:0] a, output logic [7:0] y);
  assign y = a[0] + a[1];
endmodule
module packed_array_port (input logic [7:0] p, input logic [7:0] q, output logic [7:0] y, output logic ok);
  packed_array_port_sub u_sub (.a({q, p}), .y(y));
  assign ok = (y == p + q);
endmodule
