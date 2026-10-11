// expect: ERROR
// slang: OK
package pk;
  typedef enum logic [1:0] {A, B, C} st_e;
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  localparam int W = 8;
  function automatic logic [7:0] inc(logic [7:0] x); inc = x + 8'd1; endfunction
endpackage

import pk::*;
module pkg_import_unit_type (input logic [7:0] a, output logic [3:0] y, output logic ok);
  pair_t s;
  assign s = a;
  assign y = s.lo;
  assign ok = (y == a[3:0]);
endmodule
