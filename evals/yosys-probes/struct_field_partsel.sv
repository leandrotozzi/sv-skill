// expect: OK
module struct_field_partsel (input logic [7:0] a, output logic [1:0] y, output logic ok);
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  pair_t s;
  assign s = a;
  assign y = s.hi[2:1];
  assign ok = (y == a[6:5]);
endmodule
