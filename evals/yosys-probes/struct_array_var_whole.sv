// expect: WRONG
// note: pair_t [1:0] s collapses to one pair_t (8 bits); the outer packed dimension is dropped silently.
module struct_array_var_whole (input logic [15:0] a, input logic i, output logic [3:0] y, output logic ok);
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  pair_t [1:0] s;
  pair_t e;
  assign s = a;
  assign e = s[i];
  assign y = e.lo;
  assign ok = (y == (i ? a[11:8] : a[3:0]));
endmodule
