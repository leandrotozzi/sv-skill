// expect: ERROR
// slang: OK
module inside_op (input logic [3:0] a, output logic y, output logic ok);
  assign y = a inside {4'd1, 4'd2, [4'd8:4'd9]};
  assign ok = (y == (a == 1 || a == 2 || a == 8 || a == 9));
endmodule
