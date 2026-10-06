// expect: WRONG
// note: s[1].lo is taken as a new implicit wire, left undriven.
module struct_array_field_const (input logic [15:0] a, output logic [3:0] y, output logic ok);
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  pair_t [1:0] s;
  assign s = a;
  assign y = s[1].lo;
  assign ok = (y == a[11:8]);
endmodule
