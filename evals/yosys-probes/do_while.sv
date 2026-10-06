// expect: ERROR
module do_while (input logic [7:0] a, output logic [7:0] y, output logic ok);
  int i;
  always_comb begin
    y = '0; i = 0;
    do begin y[i] = a[i]; i = i + 1; end while (i < 8);
  end
  assign ok = (y == a);
endmodule
