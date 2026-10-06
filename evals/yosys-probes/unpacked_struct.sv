// expect: ERROR
module unpacked_struct (input logic [7:0] a, output logic [7:0] y, output logic ok);
  typedef struct { logic [3:0] hi; logic [3:0] lo; } up_t;
  up_t s;
  assign s.hi = a[7:4];
  assign s.lo = a[3:0];
  assign y = {s.lo, s.hi};
  assign ok = (y == {a[3:0], a[7:4]});
endmodule
