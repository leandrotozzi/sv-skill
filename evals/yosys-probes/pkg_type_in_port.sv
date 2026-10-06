// expect: OK
package pk;
  typedef enum logic [1:0] {A, B, C} st_e;
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  localparam int W = 8;
  function automatic logic [7:0] inc(logic [7:0] x); inc = x + 8'd1; endfunction
endpackage

module pkg_type_in_port (input pk::pair_t a, output pk::st_e y, output logic ok);
  assign y = pk::st_e'(a.lo[1:0]);
  assign ok = (y == a[1:0]);
endmodule
