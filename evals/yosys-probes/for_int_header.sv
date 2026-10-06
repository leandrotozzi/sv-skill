// expect: OK
module for_int_header (input logic [7:0] a, output logic [7:0] y, output logic ok);
  always_comb begin
    y = '0;
    for (int i = 0; i < 8; i++) y[i] = a[7-i];
  end
  assign ok = (y == {a[0],a[1],a[2],a[3],a[4],a[5],a[6],a[7]});
endmodule
