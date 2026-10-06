// expect: OK
module union_packed (input logic [7:0] a, output logic [3:0] y, output logic ok);
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  typedef union packed { logic [7:0] raw; pair_t p; } u_t;
  u_t u;
  assign u.raw = a;
  assign y = u.p.hi;
  assign ok = (y == a[7:4]);
endmodule
