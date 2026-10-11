// expect: ERROR
// slang: OK
module enum_first_last_num (output logic [3:0] y, output logic ok);
  typedef enum logic [1:0] {S0, S1, S2} st_e;
  st_e s;
  assign y = 4'(s.num());
  assign ok = (y == 4'd3);
endmodule
