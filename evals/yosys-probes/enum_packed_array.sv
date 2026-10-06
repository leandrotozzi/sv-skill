// expect: OK
module enum_packed_array (input logic [7:0] a, input logic [1:0] i, output logic [1:0] y, output logic ok);
  typedef enum logic [1:0] {S0, S1, S2, S3} st_e;
  st_e [3:0] v;
  assign v = a;
  assign y = v[i];
  assign ok = (y == a[i*2 +: 2]);
endmodule
