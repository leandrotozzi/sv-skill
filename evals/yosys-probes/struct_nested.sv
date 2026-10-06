// expect: OK
module struct_nested (input logic [11:0] a, output logic [3:0] y, output logic ok);
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  typedef struct packed { logic [3:0] tag; pair_t p; } outer_t;
  outer_t s;
  assign s = a;
  assign y = s.p.lo;
  assign ok = (y == a[3:0]);
endmodule
