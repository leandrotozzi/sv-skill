// expect: OK
package pk;
  typedef enum logic [1:0] {A, B, C} st_e;
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  localparam int W = 8;
  function automatic logic [7:0] inc(logic [7:0] x); inc = x + 8'd1; endfunction
endpackage

module pkg_scoped (input logic [7:0] a, output logic [7:0] y, output logic ok);
  pk::pair_t s;
  pk::st_e st;
  assign s = a;
  assign st = pk::B;
  assign y = pk::inc({s.lo, s.hi}) + 8'(pk::W) + 8'(st);
  assign ok = (y == {a[3:0], a[7:4]} + 8'd1 + 8'd8 + 8'd1);
endmodule
