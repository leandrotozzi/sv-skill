// expect: ERROR
module struct_array_field (input logic [15:0] a, input logic i, output logic [3:0] y, output logic ok);
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  pair_t [1:0] s;
  assign s = a;
  assign y = s[i].lo;
  assign ok = (y == (i ? a[11:8] : a[3:0]));
endmodule
