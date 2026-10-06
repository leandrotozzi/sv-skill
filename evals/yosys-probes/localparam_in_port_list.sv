// expect: OK
module localparam_in_port_list #(parameter int IntBits = 4, parameter int FracBits = 12,
    localparam int Width = IntBits + FracBits) (input logic [Width-1:0] a, output logic [Width-1:0] y, output logic ok);
  assign y = a;
  assign ok = (Width == 16) && (y == a);
endmodule
