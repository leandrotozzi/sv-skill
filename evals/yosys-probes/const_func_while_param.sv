// expect: OK
module const_func_while_param (output logic [7:0] y, output logic ok);
  function automatic int lg(int v); int r; r = 0; while ((1 << r) < v) r = r + 1; lg = r; endfunction
  localparam int L = lg(100);
  assign y = 8'(L);
  assign ok = (y == 8'd7);
endmodule
