// expect: OK
// note: portable rewrite for a packed array of structs: store flat vectors, read an element into a struct variable.
module struct_array_flat_rewrite (input logic [15:0] a, input logic i, output logic [3:0] y, output logic ok);
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  pair_t e;
  logic [1:0][$bits(e)-1:0] s;
  assign s = a;
  assign e = s[i];
  assign y = e.lo;
  assign ok = (y == (i ? a[11:8] : a[3:0]));
endmodule
