// expect: OK
module struct_2d_field (input logic [15:0] a, input logic i, output logic [3:0] y, output logic ok);
  typedef struct packed { logic [1:0][3:0] f; logic [7:0] g; } st_t;
  st_t s;
  assign s = a;
  assign y = s.f[i];
  assign ok = (y == (i ? a[15:12] : a[11:8]));
endmodule
