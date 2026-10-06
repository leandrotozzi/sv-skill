// expect: ERROR
module func_packed2d_return (input logic [15:0] a, input logic i, output logic [7:0] y, output logic ok);
  function automatic logic [1:0][7:0] swap(logic [1:0][7:0] x);
    swap = {x[0], x[1]};
  endfunction
  logic [1:0][7:0] r;
  assign r = swap(a);
  assign y = r[i];
  assign ok = (y == (i ? a[7:0] : a[15:8]));
endmodule
