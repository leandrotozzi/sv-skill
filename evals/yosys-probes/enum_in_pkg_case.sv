// expect: OK
package pk;
  typedef enum logic [1:0] {A, B, C} st_e;
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  localparam int W = 8;
  function automatic logic [7:0] inc(logic [7:0] x); inc = x + 8'd1; endfunction
endpackage

module enum_in_pkg_case (input logic [1:0] a, output logic [1:0] y, output logic ok);
  pk::st_e s;
  assign s = pk::st_e'(a);
  always_comb begin
    unique case (s)
      pk::A: y = 2'd1;
      pk::B: y = 2'd2;
      default: y = 2'd0;
    endcase
  end
  assign ok = (y == ((a == 0) ? 2'd1 : (a == 1) ? 2'd2 : 2'd0));
endmodule
