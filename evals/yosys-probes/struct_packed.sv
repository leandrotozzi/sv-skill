// expect: OK
module struct_packed (input logic [7:0] a, output logic [3:0] y, output logic ok);
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  pair_t s;
  assign s = a;
  assign y = s.hi ^ s.lo;
  assign ok = (y == (a[7:4] ^ a[3:0]));
endmodule
