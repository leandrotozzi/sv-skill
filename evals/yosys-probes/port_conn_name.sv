// expect: OK
module port_conn_name_sub (input logic [7:0] a, output logic [7:0] y);
  assign y = a + 8'd1;
endmodule
module port_conn_name (input logic [7:0] a, output logic [7:0] y, output logic ok);
  port_conn_name_sub u_sub (.a, .y);
  assign ok = (y == a + 8'd1);
endmodule
