// expect: OK
module struct_signed_packed (input logic [7:0] a, output logic [8:0] y, output logic ok);
  typedef struct packed signed { logic [3:0] hi; logic [3:0] lo; } sp_t;
  sp_t s;
  assign s = a;
  assign y = s;
  assign ok = (y == {a[7], a});
endmodule
