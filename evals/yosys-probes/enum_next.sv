// expect: ERROR
module enum_next (input logic [1:0] a, output logic [1:0] y, output logic ok);
  typedef enum logic [1:0] {S0, S1, S2, S3} st_e;
  st_e s;
  assign s = st_e'(a);
  assign y = s.next();
  assign ok = (y == a + 2'd1);
endmodule
