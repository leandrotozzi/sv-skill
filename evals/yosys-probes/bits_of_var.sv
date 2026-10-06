// expect: OK
module bits_of_var (output logic [7:0] y, output logic ok);
  typedef struct packed { logic [3:0] hi; logic [2:0] lo; } t_t;
  t_t v;
  assign v = '0;
  assign y = 8'($bits(v));
  assign ok = (y == 8'd7);
endmodule
