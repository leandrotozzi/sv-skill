// expect: ERROR
package pk;
  typedef enum logic [1:0] {A, B, C} st_e;
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  localparam int W = 8;
  function automatic logic [7:0] inc(logic [7:0] x); inc = x + 8'd1; endfunction
endpackage

package pk2;
  function automatic logic [7:0] dbl(logic [7:0] x); return x << 1; endfunction
endpackage
module func_in_pkg_with_return (input logic [7:0] a, output logic [7:0] y, output logic ok);
  assign y = pk2::dbl(a);
  assign ok = (y == {a[6:0], 1'b0});
endmodule
