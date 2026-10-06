// expect: ERROR
module unpacked_port_sub (input logic [7:0] a [2], output logic [7:0] y);
  assign y = a[0] + a[1];
endmodule
module unpacked_port (input logic [7:0] p, input logic [7:0] q, output logic [7:0] y, output logic ok);
  logic [7:0] arr [2];
  assign arr[0] = p;
  assign arr[1] = q;
  unpacked_port_sub u_sub (.a(arr), .y(y));
  assign ok = (y == p + q);
endmodule
