// expect: OK
module type_cast_enum (input logic [1:0] a, output logic [1:0] y, output logic ok);
  typedef enum logic [1:0] {S0, S1, S2, S3} st_e;
  st_e s;
  assign s = st_e'(a);
  assign y = s;
  assign ok = (y == a);
endmodule
