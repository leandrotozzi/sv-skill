// expect: ERROR
package pk;
  typedef enum logic [1:0] {A, B, C} st_e;
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  localparam int W = 8;
  function automatic logic [7:0] inc(logic [7:0] x); inc = x + 8'd1; endfunction
endpackage

import pk::*;
module pkg_import_unit (input logic [7:0] a, output logic [7:0] y, output logic ok);
  assign y = inc(a);
  assign ok = (y == a + 8'd1);
endmodule
