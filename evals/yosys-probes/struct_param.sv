// expect: OK
module struct_param (output logic [7:0] y, output logic ok);
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  localparam pair_t P = 8'h5a;
  assign y = {P.lo, P.hi};
  assign ok = (y == 8'ha5);
endmodule
