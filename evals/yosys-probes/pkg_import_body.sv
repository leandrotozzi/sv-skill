// expect: ERROR
package pk;
  typedef enum logic [1:0] {A, B, C} st_e;
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  localparam int W = 8;
  function automatic logic [7:0] inc(logic [7:0] x); inc = x + 8'd1; endfunction
endpackage

module pkg_import_body (input logic [7:0] a, output logic [7:0] y, output logic ok);
  import pk::*;
  pair_t s;
  assign s = a;
  assign y = inc(s) + 8'(W);
  assign ok = (y == a + 8'd9);
endmodule
