// expect: ERROR
// slang: OK
module bits_of_type (output logic [7:0] y, output logic ok);
  typedef struct packed { logic [3:0] hi; logic [2:0] lo; } t_t;
  assign y = 8'($bits(t_t));
  assign ok = (y == 8'd7);
endmodule
